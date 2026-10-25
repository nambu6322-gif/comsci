from pathlib import Path
import json,os
from playwright.sync_api import sync_playwright
base=os.getenv('TEST_BASE_URL','http://127.0.0.1:8765')
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
 context=browser.new_context(viewport={'width':390,'height':844},has_touch=True)
 page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.route('**/api/engine/health',lambda r:r.fulfill(json={'ready':True,'corpus_documents':122}))
 state={'failure':False};received=[]
 def content(route):
  req=route.request;received.append(req.post_data_json)
  assert req.headers['authorization']=='Bearer fixture-link-access'
  assert req.post_data_json=={'url':'https://news.kbs.co.kr/article/fixture','duration_seconds':60,'start_seconds':15}
  events=[{'event':'content','content':{'title':'<img src=x onerror=alert(1)> 기사','url':'https://news.kbs.co.kr/article/fixture','scope':'본문에서 최대 3개 주장','excerpt':'추출한 기사 내용','claims':[{'claim':'금성은 태양계에서 가장 뜨거운 행성이다.'}]}},{'event':'result','result':{'status':'analyzed','verdict':'SUPPORTS','claims':[{'claim':'금성은 태양계에서 가장 뜨거운 행성이다.','verdict':'SUPPORTS','reason':'독립 원문과 대조한 결과','evidence':[{'quote':"It's the hottest planet in our solar system",'source':'https://science.nasa.gov/venus/venus-facts/'}]}]}}]
  events.append({'event':'error','message':'추가 주장 검색 한도에 도달했습니다.'} if state['failure'] else {'event':'done'})
  route.fulfill(content_type='application/x-ndjson',body=''.join(json.dumps(x,ensure_ascii=False)+'\n' for x in events))
 page.route('**/api/engine/content/stream',content)
 page.goto(base,wait_until='networkidle');page.locator('#openContentCheck').click()
 assert page.locator('#webMode').input_value()=='url' and page.locator('#webUrl').is_visible()
 page.locator('#webUrl').fill('https://news.kbs.co.kr/article/fixture');page.locator('#webVideoStart').fill('15');page.locator('#webKey').fill('fixture-link-access');page.locator('#webSubmit').click()
 page.wait_for_function('document.getElementById("webResult").innerText.includes("확인 결과 1개")')
 assert page.locator('#webResult img').count()==0
 assert page.locator('#webResult blockquote').inner_text()=="It's the hottest planet in our solar system"
 assert page.locator('#webResult a').count()==2
 assert '영상·기사 전체의 진위 판정은 아닙니다' in page.locator('#webResult').inner_text()
 state['failure']=True;page.locator('#webSubmit').click();page.wait_for_function('document.getElementById("webResult").innerText.includes("추가 주장 검색 한도")')
 assert page.locator('#webResult blockquote').count()==1
 for width in [320,390,768,1024]:
  page.set_viewport_size({'width':width,'height':844});assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
 page.locator('#webClose').click();assert page.locator('#webKey').input_value()==''
 assert len(received)==2 and not errors,errors
 browser.close()
print('PASS video/article link entry, scoped request, safe extracted text, separate source/evidence links, per-claim verdict rendering, partial result preservation, responsive widths and cleared access key; fixture backend.')
