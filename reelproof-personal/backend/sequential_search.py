"""Explicit sequential cosine search for LightRAG original-text chunks.

The loop compares every stored vector once. It keeps the best k matches instead
of stopping at the first plausible match. No LLM is called for individual rows.
"""
import heapq
import logging
import numpy as np

logger = logging.getLogger('reelproof.retrieval')
STRATEGY = 'sequential_cosine_scan'


def sequential_top_k(query, vectors, top_k=4, threshold=None):
    """Return (row_index, similarity) in descending similarity order.

    Time: O(N * D + N * log(k)); auxiliary space: O(k + D).
    N is the number of chunks and D is the embedding dimension. Equal scores
    keep original row order so results are deterministic.
    """
    query = np.asarray(query, dtype=np.float32)
    if query.ndim != 1 or vectors.ndim != 2 or vectors.shape[1] != len(query):
        raise ValueError('Query and stored vector dimensions must match')
    if top_k <= 0:
        return []
    norm = float(np.linalg.norm(query))
    if not np.isfinite(query).all() or not np.isfinite(norm) or norm == 0:
        raise ValueError('Query embedding must be finite and nonzero')
    query = query / norm
    best = []
    # SEQUENTIAL SEARCH: visit stored vectors one by one, from first to last.
    # LightRAG/NanoVectorDB has already normalized the stored vectors.
    for index, vector in enumerate(vectors):
        similarity = float(np.dot(vector, query))
        if not np.isfinite(similarity):
            continue
        if threshold is not None and similarity < threshold:
            continue
        candidate = (similarity, -index)
        if len(best) < top_k:
            heapq.heappush(best, candidate)
        elif candidate > best[0]:
            heapq.heapreplace(best, candidate)
    return [(-negative_index, score) for score, negative_index in sorted(best, reverse=True)]


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
    rag.chunks_vdb.query = SequentialChunkQuery(rag.chunks_vdb)
    rag.reelproof_retrieval_strategy = STRATEGY
