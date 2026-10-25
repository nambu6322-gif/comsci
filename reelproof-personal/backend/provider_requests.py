"""One start every four seconds for this worker's Gemini inference requests."""
import asyncio,time,re
from types import SimpleNamespace

MIN_INTERVAL_SECONDS = 4.0

class RequestSpacing:
 def __init__(self,interval=MIN_INTERVAL_SECONDS,clock=time.monotonic,sleep=asyncio.sleep):
  self.interval=interval;self.clock=clock;self.sleep=sleep
  self.lock=asyncio.Lock();self.last_start=None;self.requests_started=0;self.recent_gaps=[]
 async def wait(self):
  async with self.lock:
   if self.last_start is not None:
    delay=self.interval-(self.clock()-self.last_start)
    while delay>0:
     await self.sleep(delay);delay=self.interval-(self.clock()-self.last_start)
   now=self.clock()
   if self.last_start is not None:self.recent_gaps=(self.recent_gaps+[now-self.last_start])[-8:]
   self.last_start=now;self.requests_started+=1
 def snapshot(self):
  return {"minimum_interval_seconds":self.interval,"scope":"per_server_worker","requests_started":self.requests_started,"recent_start_gaps_seconds":[round(g,3) for g in self.recent_gaps]}

class PacedModels:
 def __init__(self,models,spacing):self.models=models;self.spacing=spacing
 async def generate_content(self,*args,**kwargs):
  await self.spacing.wait()
  return await self.models.generate_content(*args,**kwargs)
 async def embed_content(self,*args,**kwargs):
  await self.spacing.wait()
  return await self.models.embed_content(*args,**kwargs)
 def __getattr__(self,name):return getattr(self.models,name)

class PacedGemini:
 def __init__(self,client):
  self.client=client;self.request_spacing=RequestSpacing()
  self.aio=SimpleNamespace(models=PacedModels(client.aio.models,self.request_spacing))
 def __getattr__(self,name):return getattr(self.client,name)

def quota_details(error):
 """Expose metric/limit/retry metadata only; never raw provider messages."""
 value=getattr(error,'details',{})
 if not isinstance(value,dict):value={}
 value=value.get('error',value)
 details=value.get('details',[]) if isinstance(value,dict) else []
 result={'provider_status':429,'violations':[],'retry_after_seconds':60}
 for item in details if isinstance(details,list) else []:
  if not isinstance(item,dict):continue
  delay=item.get('retryDelay')
  if isinstance(delay,str) and re.fullmatch(r'\d+(?:\.\d+)?s',delay):result['retry_after_seconds']=max(1,min(86400,int(float(delay[:-1])+1)))
  for violation in item.get('violations',[]) if isinstance(item.get('violations'),list) else []:
   if not isinstance(violation,dict):continue
   clean={}
   for key in ['quotaMetric','quotaId','quotaValue']:
    field=violation.get(key)
    if isinstance(field,(str,int,float)) and re.fullmatch(r'[A-Za-z0-9_.:/-]{1,200}',str(field)):clean[key]=str(field)
   dimensions=violation.get('quotaDimensions',{})
   if isinstance(dimensions,dict):
    clean['dimensions']={k:str(dimensions[k]) for k in ['model','location'] if k in dimensions and re.fullmatch(r'[A-Za-z0-9_.:/-]{1,100}',str(dimensions[k]))}
   result['violations'].append(clean)
 return result


def request_status(client):
 spacing=getattr(client,'request_spacing',None)
 return spacing.snapshot() if isinstance(spacing,RequestSpacing) else {'minimum_interval_seconds':MIN_INTERVAL_SECONDS,'scope':'per_server_worker','requests_started':0,'recent_start_gaps_seconds':[]}
