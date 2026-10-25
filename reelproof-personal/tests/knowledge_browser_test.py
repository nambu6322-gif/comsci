from playwright.sync_api import sync_playwright
import os,json
base=os.getenv('TEST_BASE_URL','http://127.0.0.1:8765')
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
 page=browser.new_page(viewport={'width':390,'height':844});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.route('**/api/engine/health',lambda r:r.fulfill(json={'ready':True,'verification_mode':'knowledge_only','web_search_enabled':False,'api_request_min_interval_seconds':4,'corpus_documents':0}))
 result={'status':'analyzed','verdict':'NOT_ENOUGH_INFO','verification_mode':'knowledge_only','knowledge_assessment':{'assessment':'LIKELY_TRUE','externally_verified':False},'message':'Gemini 자체지식 추정입니다. 외부 근거 검증이 아닙니다.','claims':[{'claim':'지구는 태양계에서 세 번째 행성이다.','verdict':'NOT_ENOUGH_INFO','verification_mode':'knowledge_only','knowledge_assessment':{'assessment':'LIKELY_TRUE','externally_verified':False},'reason':'외부 근거 검증이 아닌 AI 추정입니다.','evidence':[]}]}
 def respond(route):
  assert route.request.headers['authorization']=='Bearer fixture-knowledge-ui'
  route.fulfill(json=result)
 page.route('**/api/engine/analyze',respond)
 page.goto(base,wait_until='networkidle');page.locator('#openWebCheck').click();page.wait_for_function('!document.getElementById("webSubmit").disabled')
 assert '자체지식' in page.locator('#webStatus').inner_text() and page.locator('#webSearch').is_disabled()
 page.locator('#webMode').select_option('text');page.locator('#webText').fill('지구는 태양계에서 세 번째 행성이다.');page.locator('#webKey').fill('fixture-knowledge-ui');page.locator('#webSubmit').click()
 page.wait_for_function('document.getElementById("webResult").innerText.includes("AI 추정 · 사실일 가능성이 높음")')
 assert page.locator('#webResult blockquote').count()==0 and '원문 근거 있음' not in page.locator('#webResult').inner_text()
 assert '꺼져 있습니다' in page.locator('#verificationNote').inner_text() and not errors,errors
 browser.close()
print('PASS knowledge-only browser UI: explicit AI assessment, disabled external-search option, four-second status, no fabricated evidence links/quotes or verified-fact label.')
