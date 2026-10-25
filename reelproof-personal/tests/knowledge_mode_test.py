import asyncio,json,os,sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch,AsyncMock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
os.environ['VERIFICATION_MODE']='knowledge_only'
os.environ['REELPROOF_TOKEN']='fixture-knowledge-access';os.environ.pop('GEMINI_API_KEY',None)
import app as backend
from knowledge_judgment import assess
from fastapi.testclient import TestClient
class Model:
 def __init__(self):self.calls=[]
 async def generate_content(self,**kw):
  self.calls.append(kw);assert not kw['config'].tools
  body=json.loads(kw['contents']);assert set(body)=={'claim','current_date_utc'}
  return SimpleNamespace(text=json.dumps({'assessment':'LIKELY_TRUE','reason':'내부 지식에서는 알려진 사실입니다.'}))
async def main():
 model=Model();backend.app.state.gemini=SimpleNamespace(aio=SimpleNamespace(models=model));backend.app.state.model_id='fixture';backend.app.state.provider='gemini';backend.app.state.ready=True
 rag=SimpleNamespace(aquery_data=AsyncMock(side_effect=AssertionError('RAG must be disabled')));backend.app.state.rag=rag
 with patch('web_evidence.discover_originals',AsyncMock(side_effect=AssertionError('Search must be disabled'))):
  result=await backend.verify_claim('지구는 태양계의 세 번째 행성이다.',web=True,exclude_sources=('https://example.invalid',))
 assert result['verdict']=='NOT_ENOUGH_INFO' and result['evidence']==[] and result['knowledge_assessment']['assessment']=='LIKELY_TRUE' and not result['knowledge_assessment']['externally_verified']
 assert rag.aquery_data.await_count==0
 backend.cache.clear()
 a=await backend.cached_verification('Cached fixture claim.',web=False)
 b=await backend.cached_verification('Cached fixture claim.',web=True,exclude_sources=('https://example.invalid',))
 assert a==b and len(model.calls)==2
 results=[r async for _,r in backend.completed_claims([('Same knowledge fixture.',.9)],fallback_web=True)]
 assert len(model.calls)==3 and results[0]['verification_mode']=='knowledge_only'
asyncio.run(main())
with TestClient(backend.app) as client:
 backend.app.state.ready=True;backend.app.state.provider='gemini';backend.app.state.model_id='fixture';backend.app.state.gemini=SimpleNamespace(aio=SimpleNamespace(models=Model()));backend.cache.clear()
 response=client.post('/v1/analyze/web',headers={'Authorization':'Bearer fixture-knowledge-access'},json={'text':'Fresh fixture knowledge claim.','source':'manual'})
 assert response.status_code==200,response.text
 result=response.json();assert result['verification_mode']=='knowledge_only' and result['knowledge_assessment']['assessment']=='LIKELY_TRUE' and result['verdict']=='NOT_ENOUGH_INFO'
 health=client.get('/health').json();assert not health['web_search_enabled'] and health['retrieval_strategy']=='disabled_knowledge_only' and health['api_request_min_interval_seconds']==4
 response=client.post('/v1/analyze/stream',headers={'Authorization':'Bearer fixture-knowledge-access'},json={'text':'Another fixture knowledge claim.','source':'manual'})
 events=[json.loads(x) for x in response.text.splitlines()];assert events[-1]['event']=='done' and events[0]['result']['knowledge_assessment']['assessment']=='LIKELY_TRUE'
print('PASS internal-knowledge-only judgment: no search/RAG/tool calls, separate unverified AI assessment, no invented evidence, mode-specific shared cache, compatible JSON/stream API and four-second configuration.')
