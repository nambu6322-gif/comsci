"""Python buffer bridge to the C sequential search used by LightRAG.

The loop compares every stored vector once. It keeps the best k matches instead
of stopping at the first plausible match. No LLM is called for individual rows.
"""
import ctypes
from functools import lru_cache
import logging
from pathlib import Path
import platform
import numpy as np

logger = logging.getLogger('reelproof.retrieval')
STRATEGY = 'sequential_cosine_scan'


@lru_cache(maxsize=1)
def load_native():
    suffix = '.dll' if platform.system() == 'Windows' else '.dylib' if platform.system() == 'Darwin' else '.so'
    library = ctypes.CDLL(str(Path(__file__).with_name('_reelproof_scan' + suffix)))
    library.rp_scan_implementation.restype = ctypes.c_char_p
    if library.rp_scan_implementation() != b'c-sequential-cosine-v1':
        raise RuntimeError('Unexpected native search implementation')
    pointer = ctypes.POINTER(ctypes.c_float)
    library.rp_sequential_search.argtypes = [pointer, pointer, ctypes.c_size_t,
        ctypes.c_size_t, ctypes.c_size_t, ctypes.c_int, ctypes.c_double,
        ctypes.POINTER(ctypes.c_size_t), pointer, ctypes.POINTER(ctypes.c_size_t)]
    library.rp_sequential_search.restype = ctypes.c_int
    return library


def sequential_top_k(query, vectors, top_k=4, threshold=None):
    """Call the actual C scan; Python only prepares and returns typed buffers."""
    query = np.ascontiguousarray(query, dtype=np.float32)
    vectors = np.ascontiguousarray(vectors, dtype=np.float32)
    if query.ndim != 1 or vectors.ndim != 2 or vectors.shape[1] != len(query):
        raise ValueError('Query and stored vector dimensions must match')
    if top_k <= 0:
        return []
    capacity = min(top_k, max(len(vectors), 1))
    indices = np.empty(capacity, dtype=np.uintp)
    scores = np.empty(capacity, dtype=np.float32)
    count = ctypes.c_size_t()
    pointer = ctypes.POINTER(ctypes.c_float)
    status = load_native().rp_sequential_search(
        query.ctypes.data_as(pointer), vectors.ctypes.data_as(pointer),
        len(vectors), len(query), capacity, threshold is not None,
        float(threshold) if threshold is not None else 0.0,
        indices.ctypes.data_as(ctypes.POINTER(ctypes.c_size_t)),
        scores.ctypes.data_as(pointer), ctypes.byref(count))
    if status == -3: raise MemoryError('Unable to allocate C query buffer')
    if status: raise ValueError('Invalid C search dimensions, threshold or embedding')
    return list(zip(indices[:count.value].tolist(), scores[:count.value].tolist()))


class SequentialChunkQuery:
    """Replace only this LightRAG instance's chunk query; keep its storage IO."""
    def __init__(self, storage):
        self.storage = storage

    async def __call__(self, query, top_k, query_embedding=None):
        from lightrag.constants import DEFAULT_QUERY_PRIORITY
        if query_embedding is None:
            values = await self.storage.embedding_func(
                [query], context='query', _priority=DEFAULT_QUERY_PRIORITY
            )
            query_embedding = values[0]
        # Use LightRAG's reload-aware view. Do not await during the scan or hold
        # the live storage reference across an await; its writes are synchronous.
        data = await self.storage.client_storage
        vectors, records = data['matrix'], data['data']
        if len(vectors) != len(records):
            raise ValueError('Stored chunk vectors and metadata must align')
        matches = sequential_top_k(query_embedding, vectors, top_k,
                                   self.storage.cosine_better_than_threshold)
        logger.info('retrieval strategy=%s scanned_vectors=%d matches=%d',
                    STRATEGY, len(records), len(matches))
        return [{
            **{k: v for k, v in records[index].items()
               if k not in ('vector', '__vector__', '__write_seq__')},
            'id': records[index]['__id__'],
            'distance': score,
            'created_at': records[index].get('__created_at__'),
        } for index, score in matches]


def install_sequential_search(rag):
    """Wire this scan into LightRAG mode='naive' without editing site-packages."""
    from lightrag.kg.nano_vector_db_impl import NanoVectorDBStorage
    if not isinstance(rag.chunks_vdb, NanoVectorDBStorage):
        raise TypeError('Sequential search requires NanoVectorDB chunk storage')
    load_native()  # Fail initialization if the compiled C implementation is absent.
    rag.chunks_vdb.query = SequentialChunkQuery(rag.chunks_vdb)
    rag.reelproof_retrieval_strategy = STRATEGY
    rag.reelproof_retrieval_implementation = "c"
