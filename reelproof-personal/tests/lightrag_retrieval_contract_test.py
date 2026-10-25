"""Real LightRAG source-only retrieval, with a fixed query vector and no provider call."""
import asyncio,base64,json,shutil,sys,tempfile,zlib
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
from app import Utf8BudgetTokenizer,sources
from sequential_search import install_sequential_search,STRATEGY
from lightrag import LightRAG,QueryParam
from lightrag.utils import EmbeddingFunc,Tokenizer
from lightrag.kg.shared_storage import initialize_pipeline_status
async def main():
 snapshot=ROOT/'backend/index_snapshot'
 record=json.loads((snapshot/'vdb_chunks.json').read_text())['data'][0]
 vector=np.frombuffer(zlib.decompress(base64.b64decode(record['vector'])),dtype=np.float16).astype(np.float32)
 async def embed(texts):return np.array([vector for _ in texts])
 async def no_llm(*args,**kwargs):raise AssertionError('Retrieval must not generate keywords or an answer')
 with tempfile.TemporaryDirectory() as directory:
  shutil.copytree(snapshot,directory,dirs_exist_ok=True)
  rag=LightRAG(working_dir=directory,llm_model_func=no_llm,embedding_func=EmbeddingFunc(embedding_dim=768,max_token_size=8192,func=embed),tokenizer=Tokenizer(model_name='utf8-byte-budget',tokenizer=Utf8BudgetTokenizer()),chunk_token_size=4000,chunk_overlap_token_size=200)
  await rag.initialize_storages();await initialize_pipeline_status()
  install_sequential_search(rag)
  assert rag.reelproof_retrieval_strategy==STRATEGY
  try:
   result=await asyncio.wait_for(rag.aquery_data('original document retrieval contract',param=QueryParam(mode='naive',chunk_top_k=4,max_total_tokens=16000,include_references=True,enable_rerank=False)),10)
   assert result['status']=='success' and result['data']['chunks'],result
   refs={r['reference_id']:r['file_path'] for r in result['data']['references']}
   assert all(sources.get(path,path).startswith('https://') for path in refs.values()),refs
   for chunk in result['data']['chunks']:
    assert chunk['reference_id'] in refs
    assert chunk['content'] in '\n'.join(p.read_text() for p in (ROOT/'backend/data').glob('*.txt'))
   print('PASS actual LightRAG sequential vector retrieval: original chunks and reference IDs; zero LLM calls. Query vector is a fixture, not a semantic accuracy evaluation.')
  finally:await rag.finalize_storages()
asyncio.run(main())
