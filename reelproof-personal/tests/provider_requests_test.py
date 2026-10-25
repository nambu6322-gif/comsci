import asyncio,sys
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from provider_requests import RequestSpacing,PacedModels,quota_details,MIN_INTERVAL_SECONDS
async def main():
 now=[0.0];starts=[]
 async def sleep(delay):now[0]+=delay;await asyncio.sleep(0)
 class Models:
  async def generate_content(self,**kw):starts.append(('generation',now[0]));await asyncio.sleep(0);return 'generated'
  async def embed_content(self,**kw):starts.append(('embedding',now[0]));await asyncio.sleep(0);return 'embedded'
 paced=PacedModels(Models(),RequestSpacing(clock=lambda:now[0],sleep=sleep))
 values=await asyncio.gather(paced.generate_content(),paced.embed_content(),paced.generate_content())
 assert values==['generated','embedded','generated'] and [t for _,t in starts]==[0,4,8],starts
 assert MIN_INTERVAL_SECONDS==4
 error=SimpleNamespace(details={'error':{'message':'secret-and-claim-must-not-leak','details':[{'violations':[{'quotaMetric':'generativelanguage.googleapis.com/test','quotaId':'PerDayQuota','quotaValue':'0','quotaDimensions':{'model':'fixture','location':'global','project':'private-project'}}]},{'retryDelay':'12.3s'}]}})
 safe=quota_details(error)
 assert safe['retry_after_seconds']==13 and safe['violations'][0]['quotaValue']=='0' and 'secret' not in str(safe) and 'private-project' not in str(safe)
 print('PASS four-second shared start spacing across generation/ASR/search and embedding; safe quota metadata excludes provider messages and project identifiers.')
asyncio.run(main())
