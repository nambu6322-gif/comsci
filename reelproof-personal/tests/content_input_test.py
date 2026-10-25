"""URL extraction, exact-source anchoring and independent-evidence regressions."""
import asyncio,json,os,sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock,patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
os.environ['REELPROOF_TOKEN']='fixture-content-access';os.environ['WEB_SEARCH_ENABLED']='0'
os.environ.pop('GEMINI_API_KEY',None)
import content_input as content
import app as backend
from fastapi import HTTPException
from fastapi.testclient import TestClient

url='https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=1m20s'
assert content.parse_input_url(url)['start_seconds']==80
for u in ['https://youtu.be/aqz-KE-bpKQ?t=80','https://www.youtube.com/shorts/aqz-KE-bpKQ?t=80','https://www.youtube.com/embed/aqz-KE-bpKQ?start=80']:
 value=content.parse_input_url(u);assert value['url']=='https://www.youtube.com/watch?v=aqz-KE-bpKQ' and value['start_seconds']==80
assert content.parse_input_url(url,4)['start_seconds']==4
for bad in ['http://news.naver.com/a','https://127.0.0.1/a','https://localhost/a','https://news.naver.com.evil.example/a','https://user@news.naver.com/a','https://news.naver.com:444/a','https://www.youtube.com/playlist?list=anything','https://youtu.be/../../internal']:
 try:content.parse_input_url(bad)
 except HTTPException as e:assert e.status_code==422
 else:raise AssertionError(bad)
assert content.source_identity('https://n.news.naver.com/article/001/123?utm_source=x')==content.source_identity('https://n.news.naver.com/article/001/123#hello')
assert content.source_identity('https://www.bbc.co.uk/news/articles/fixture?at_medium=RSS')==content.source_identity('https://www.bbc.com/news/articles/fixture')
quote='금성은 태양계에서 가장 뜨거운 행성이다.'
assert content.anchored_claims([{'quote':quote},{'quote':'김정은은 오늘 사망했다고 발표했다.'},{'quote':quote}],quote)==[{'claim':quote}]

class Model:
 def __init__(self):self.calls=[]
 async def generate_content(self,**kwargs):
  self.calls.append(kwargs)
  return SimpleNamespace(text=json.dumps({'title':'Fixture video','transcript':quote,'claims':[{'quote':quote},{'quote':'Unsupported invented assertion.'}]},ensure_ascii=False))
async def main():
 model=Model();client=SimpleNamespace(aio=SimpleNamespace(models=model))
 video=await content.extract_content(client,'fixture-model',url,duration_seconds=60)
 assert video['kind']=='youtube' and video['scope'].startswith('영상 80~140초') and video['claims']==[{'claim':quote}]
 part=model.calls[0]['contents'][0];assert part.file_data.file_uri=='https://www.youtube.com/watch?v=aqz-KE-bpKQ' and part.video_metadata.start_offset=='80s' and part.video_metadata.end_offset=='140s'
 document={'title':'Fixture article','source':'https://news.kbs.co.kr/article/fixture','content':quote+'\n'+('다른 문단입니다.\n'*3000),'published_at':'2026-10-25'}
 with patch.object(content,'fetch_original',AsyncMock(return_value=document)):
  article=await content.extract_content(client,'fixture-model',document['source'])
 assert article['partial'] and len(article['body'])<=content.MAX_BODY and article['claims']==[{'claim':quote}]
 # The input URL must not be used as its own corroborating original.
 class Rag:
  async def aquery_data(self,*a,**kw):return {'status':'success','data':{'references':[{'reference_id':'1','file_path':document['source']},{'reference_id':'2','file_path':'https://science.nasa.gov/venus/venus-facts/'}],'chunks':[{'reference_id':'1','content':quote,'file_path':document['source']},{'reference_id':'2','content':"It's the hottest planet in our solar system",'file_path':'https://science.nasa.gov/venus/venus-facts/'}]}}
 class Judge:
  async def generate_content(self,**kw):
   data=json.loads(kw['contents']);assert [c['reference_id'] for c in data['original_chunks']]==['2']
   return SimpleNamespace(text=json.dumps({'verdict':'SUPPORTS','reason':'Independent source fixture','evidence':[{'reference_id':'2','quote':"It's the hottest planet in our solar system"}]}))
 backend.app.state.rag=Rag();backend.app.state.gemini=SimpleNamespace(aio=SimpleNamespace(models=Judge()));backend.app.state.model_id='fixture-model';backend.app.state.provider='gemini';backend.app.state.verification_models=['fixture-model']
 result=await backend.verify_claim(quote,exclude_sources=(document['source'],));assert result['verdict']=='SUPPORTS' and result['evidence'][0]['source'].startswith('https://science.nasa.gov/')
 # Exclusion context is part of the cache identity.
 backend.cache.clear();calls=[]
 async def verify(claim,web=False,exclude_sources=()):calls.append(exclude_sources);return {'verdict':'NOT_ENOUGH_INFO','reason':'Fixture','evidence':[]}
 with patch.object(backend,'verify_claim',side_effect=verify):
  await backend.cached_verification(quote)
  await backend.cached_verification(quote,exclude_sources=(document['source'],))
  await backend.cached_verification(quote,exclude_sources=(document['source'],))
 assert calls==[(),(document['source'],)]
 backend.cache.clear()
asyncio.run(main())

with TestClient(backend.app) as client:
 assert client.post('/v1/content/stream',json={'url':url}).status_code==401
 backend.app.state.ready=True;backend.app.state.provider='gemini';backend.app.state.gemini=object();backend.app.state.model_id='fixture'
 source={'kind':'article','title':'Fixture source','url':'https://news.kbs.co.kr/article/fixture','body':quote,'excerpt':quote,'scope':'Fixture selection','claims':[{'claim':quote}]}
 async def judge(claim,web=False,exclude_sources=()):
  assert source['url'] in exclude_sources
  return {'verdict':'NOT_ENOUGH_INFO','reason':'No independent original','evidence':[]}
 with patch.object(content,'extract_content',AsyncMock(return_value=source)),patch.object(backend,'verify_claim',side_effect=judge):
  response=client.post('/v1/content/stream',headers={'Authorization':'Bearer fixture-content-access'},json={'url':source['url']})
 assert response.status_code==200 and response.headers['cache-control'].startswith('no-store')
 events=[json.loads(s) for s in response.text.splitlines()]
 assert [e['event'] for e in events]==['content','result','done'] and 'body' not in events[0]['content']
 assert events[1]['result']['verdict']=='NOT_ENOUGH_INFO'
 backend.cache.clear()
 two={**source,'claims':[{'claim':'첫 번째 독립 근거 없는 주장입니다.'},{'claim':'두 번째 대조 가능한 주장입니다.'}]}
 async def partial(claim,web=False,exclude_sources=()):
  if claim.startswith('첫 번째'):raise HTTPException(503,'검색 사용 한도')
  return {'verdict':'NOT_ENOUGH_INFO','reason':'독립 근거 없음','evidence':[]}
 with patch.object(content,'extract_content',AsyncMock(return_value=two)),patch.object(backend,'verify_claim',side_effect=partial):
  response=client.post('/v1/content/stream',headers={'Authorization':'Bearer fixture-content-access'},json={'url':source['url']})
 events=[json.loads(s) for s in response.text.splitlines()]
 assert events[-1]['event']=='done' and sum(e['event']=='claim_error' for e in events)==1 and sum(e['event']=='result' for e in events)==1
 assert all('verdict' not in e for e in events if e['event']=='claim_error')
 assert client.post('/v1/content/stream',headers={'Authorization':'Bearer fixture-content-access'},json={'url':'https://127.0.0.1/private'}).status_code==422
print('PASS article/video URL normalization, private URL denial, bounded excerpts, exact source claims, Gemini clip interval, input-source exclusion, exclusion-aware cache and authenticated progressive route; network/model fixtures, no real-video accuracy claim.')
