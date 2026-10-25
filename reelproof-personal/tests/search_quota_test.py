import asyncio,sys,json,os
from pathlib import Path
from unittest.mock import patch,AsyncMock
from types import SimpleNamespace
import httpx
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
import web_evidence as web
from content_input import extract_content,_content_cache,_content_jobs
from google.genai.errors import ClientError
async def main():
 web._google_retry_at=0;web._google_quota=None;web._rss_cache.clear()
 failure=ClientError(429,{'error':{'details':[{'violations':[{'quotaMetric':'grounded_requests','quotaId':'PerDayQuota','quotaValue':'0'}]}]}})
 expected=([{'source':'https://www.bbc.com/news/articles/fixture','content':'Original independently read text.'}],{'provider':'bing_news_rss'})
 with patch.object(web,'google_originals',AsyncMock(side_effect=failure)) as google,patch.object(web,'rss_originals',AsyncMock(return_value=expected)) as rss:
  assert await web.discover_originals(None,'model','Claim one.')==expected
  assert await web.discover_originals(None,'model','Claim two.')==expected
  assert google.await_count==1 and rss.await_count==2
  assert web.discovery_status()['google_retry_after_seconds']>3500
 assert web.rss_article_url('http://www.bing.com/news/apiclick.aspx?url=https%3A%2F%2Fwww.bbc.com%2Fnews%2Fa')=='https://www.bbc.com/news/a'
 assert not web.allowed_url(web.rss_article_url('http://www.bing.com/news/apiclick.aspx?url=http%3A%2F%2F127.0.0.1%2Fprivate'))
 # RSS summaries are never original evidence; only directly fetched bodies.
 async def transport(req):
  assert req.url.host=='www.bing.com'
  return httpx.Response(200,text='<rss><channel><item><title>A tempting unsupported assertion</title><description>Not evidence</description><link>https://www.bbc.com/news/article-one</link></item><item><link>https://evil.example/private</link></item></channel></rss>')
 actual=httpx.AsyncClient
 def client(**kw):return actual(transport=httpx.MockTransport(transport),**kw)
 web._rss_cache.clear()
 document={'source':'https://www.bbc.com/news/article-one','content':'This original text was independently read.'}
 with patch.object(web.httpx,'AsyncClient',side_effect=client),patch.object(web,'fetch_original',AsyncMock(return_value=document)) as fetch:
  docs,info=await web.rss_originals('Fresh fixture claim.')
  again=await web.rss_originals('Fresh fixture claim.')
  assert docs==[document] and info['provider']=='bing_news_rss' and not info['search_summary_used_as_evidence'] and fetch.await_count==1
 assert 'tempting' not in docs[0]['content']
 # Repeated link requests reuse extraction, never another Gemini request.
 _content_cache.clear();_content_jobs.clear()
 raw={'url':'https://news.kbs.co.kr/fixture','kind':'article','scope':'본문 범위','claims':[{'claim':'선별한 완전한 주장입니다.'}]}
 with patch('content_input._extract_content',AsyncMock(return_value=raw)) as extract:
  a,b=await asyncio.gather(extract_content(None,'fixture',raw['url']),extract_content(None,'fixture',raw['url']))
  a['claims'][0]['claim']='Changed local copy'
  c=await extract_content(None,'fixture',raw['url'])
  assert extract.await_count==1 and c['claims'][0]['claim']=='선별한 완전한 주장입니다.' and c['extraction_cached']
 assert not _content_jobs
 print('PASS Google 429 cooldown, independent RSS fallback, unsafe-link rejection, no RSS prose as evidence, search cache and coalesced immutable source extraction cache.')
asyncio.run(main())
