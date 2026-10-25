"""Prepare a static Vercel release from the reviewed mobile site, without secrets."""
import argparse,gzip,hashlib,json,shutil
from pathlib import Path
import qrcode,qrcode.image.svg
from urllib.parse import urlparse
p=argparse.ArgumentParser();p.add_argument('--site-url',required=True);a=p.parse_args();u=urlparse(a.site_url)
if u.scheme!='https' or not u.hostname.endswith('.vercel.app') or u.path not in ['', '/']:raise SystemExit('Expected an HTTPS vercel.app origin')
origin=a.site_url.rstrip('/');root=Path(__file__).resolve().parents[1];out=root/'vercel-mobile';out.mkdir(exist_ok=True)
for name in ['index.html','mobile.css','mobile.mjs','icon.svg','manifest.webmanifest','release.json']:
 shutil.copy2(root/'dist'/name,out/name)
for name in ['ios-web.mjs','content-stream.mjs','ios-web.css','sw.js','recorder.mjs','ios-personal.html']:shutil.copy2(root/'web-mobile'/name,out/name)
for size in [180,192,512]:shutil.copy2(root/'web-mobile'/('icon-'+str(size)+'.png'),out/('icon-'+str(size)+'.png'))
shutil.copytree(root/'dist/downloads',out/'downloads',dirs_exist_ok=True)
(out/'assets').mkdir(exist_ok=True)
apk=(out/'downloads/reelproof-android.apk').read_bytes()
(out/'assets/reelproof-android.apk.gz').write_bytes(gzip.compress(apk,compresslevel=9,mtime=0))
(out/'downloads/reelproof-android.apk').unlink()
(out/'api').mkdir(exist_ok=True)
download_source="""import { createReadStream } from 'node:fs';
import { createGunzip } from 'node:zlib';
import { pipeline } from 'node:stream/promises';
import { join } from 'node:path';
export default async function handler(req,res){
 if(!['GET','HEAD'].includes(req.method)){res.statusCode=405;res.setHeader('Allow','GET, HEAD');res.end();return;}
 res.setHeader('Content-Type','application/vnd.android.package-archive');
 res.setHeader('Content-Disposition','attachment; filename="reelproof-android.apk"');
 res.setHeader('Cache-Control','public, max-age=0, must-revalidate');
 res.setHeader('Content-Length','APK_LENGTH');
 if(req.method==='HEAD'){res.end();return;}
 try{await pipeline(createReadStream(join(process.cwd(),'assets/reelproof-android.apk.gz')),createGunzip(),res);}
 catch{if(!res.headersSent){res.statusCode=500;res.removeHeader('Content-Length');res.end('Download unavailable');}else res.destroy();}
}
""".replace('APK_LENGTH',str(len(apk)))
(out/'api/android-download.mjs').write_text(download_source)
# Small content-addressed parts avoid retransmitting large archive requests.
semantic=(out/'downloads/reelproof-semantic-models.zip').read_bytes()
parts=out/'assets/semantic';shutil.rmtree(parts,ignore_errors=True);parts.mkdir()
for i,offset in enumerate(range(0,len(semantic),393216)):(parts/(str(i).zfill(3)+'.part')).write_bytes(semantic[offset:offset+393216])
(out/'downloads/reelproof-semantic-models.zip').unlink()
semantic_download='''import { createReadStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { join } from 'node:path';
export default async function handler(req,res){
 if(!['GET','HEAD'].includes(req.method)){res.statusCode=405;res.setHeader('Allow','GET, HEAD');res.end();return;}
 res.setHeader('Content-Type','application/zip');
 res.setHeader('Content-Disposition','attachment; filename="reelproof-semantic-models.zip"');
 res.setHeader('Cache-Control','public, max-age=0, must-revalidate');
 res.setHeader('Content-Length','ARCHIVE_LENGTH');
 if(req.method==='HEAD'){res.end();return;}
 async function* chunks(){for(let i=0;i<PART_COUNT;i++)for await(const chunk of createReadStream(join(process.cwd(),'assets/semantic',String(i).padStart(3,'0')+'.part')))yield chunk;}
 try{await pipeline(Readable.from(chunks()),res);}
 catch{if(!res.headersSent){res.statusCode=500;res.removeHeader('Content-Length');res.end('Download unavailable');}else res.destroy();}
}
'''.replace('ARCHIVE_LENGTH',str(len(semantic))).replace('PART_COUNT',str(len(list(parts.glob('*.part')))))
(out/'api/semantic-download.mjs').write_text(semantic_download)
for platform in ['android','ios']:
 qrcode.make(origin+'/?platform='+platform,image_factory=qrcode.image.svg.SvgPathImage,box_size=8,border=3).save(out/'assets'/('qr-'+platform+'.svg'))
p=out/'mobile.mjs';s=p.read_text().replace('비공개 사이트입니다. 같은 계정으로 로그인해야 열립니다.','휴대폰 카메라로 스캔하면 기종별 앱 안내 페이지가 열립니다.').replace("fetch(release.backend.endpoint+'/health'","fetch('/api/engine/health'").replace("const ios=/iPhone|iPad|iPod/i.test(navigator.userAgent)","const ios=/iPhone|iPad|iPod/i.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1)").replace("$('start').onclick=()=>{","$('start').onclick=()=>{if(!android){window.dispatchEvent(new CustomEvent('reelproof-web-check'));return;}").replace("function platform(p){const a=p==='android';","function platform(p){const a=p==='android';if(!a){window.dispatchEvent(new CustomEvent('reelproof-ios-guide'));return;}").replace('준비 상태 · 소스 다운로드','Safari 웹앱 · 설치 안내');s+="\nif(!android)document.getElementById('start').textContent='녹음·주장 확인 ↗';\n";p.write_text(s)
p=out/'index.html';s=p.read_text().replace('</head>','<meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-status-bar-style" content="default"><meta name="apple-mobile-web-app-title" content="ReelProof"><link rel="apple-touch-icon" href="/icon-180.png"><link rel="stylesheet" href="/ios-web.css"></head>').replace('<section class="downloads">','<section class="web-actions"><h2>iPhone·iPad에서도.</h2><p>홈 화면에 추가하고 직접 녹음하거나 주장을 입력하세요.<br>마이크·완료 알림 설정은 검증 화면에 있습니다.</p><button id="openWebCheck" class="sheet-button">웹앱에서 녹음·주장 확인</button><button id="openContentCheck" class="sheet-button secondary">유튜브·뉴스 기사 링크 검증</button><button id="installWeb" class="web-link">홈 화면에 추가하는 방법 ↗</button></section><section class="downloads">').replace('설치 배포 준비 중','개인 테스트 IPA · Windows 설치').replace('<script type="module" src="/mobile.mjs"></script>','<script type="module" src="/mobile.mjs"></script><script type="module" src="/ios-web.mjs"></script>');s=s.replace('src="/mobile.mjs"','src="/mobile.mjs?v=12"').replace('src="/ios-web.mjs"','src="/ios-web.mjs?v=12"').replace('</head>','<meta name="referrer" content="no-referrer"></head>');p.write_text(s)
p=out/'index.html';s=p.read_text().replace('마음 놓고 넘기세요.<br><span>확인은 ReelProof가.</span>','짧은 주장도,<br><span>근거부터 확인.</span>').replace('필요한 순간, 짧은 알림으로.','직접 녹음하고, 텍스트로 확인하세요.').replace('● 설치 앱에서 시작','● 녹음 · 텍스트 검증').replace('보고 있는 영상을,<br>근거로 확인해요.','궁금한 주장을,<br>근거로 확인해요.').replace('음성·자막에서 검증할 주장을 골라<br>원문과 대조하는 모바일 연구 앱입니다.','음성을 직접 녹음하거나 주장을 입력해<br>원문과 대조하는 모바일 연구 웹앱입니다.').replace('웹페이지에서는 다른 앱의 화면·소리를 읽을 수 없어요.<br>네이티브 앱과 시스템 녹화 동의가 필요합니다.','이 화면에서 마이크를 허용해 직접 녹음할 수 있어요.<br>다른 앱의 화면·재생 소리는 자동으로 읽지 않습니다.');p.write_text(s)
manifest=json.loads((out/'manifest.webmanifest').read_text());manifest.update(id='/',scope='/',description='음성을 직접 녹음하거나 주장을 입력해 원문 근거를 확인하는 모바일 연구 웹앱');manifest['icons']+=[{'src':'/icon-'+str(size)+'.png','sizes':str(size)+'x'+str(size),'type':'image/png'} for size in [192,512]];(out/'manifest.webmanifest').write_text(json.dumps(manifest,ensure_ascii=False))
config={'$schema':'https://openapi.vercel.sh/vercel.json','framework':None,'functions':{'api/android-download.mjs':{'includeFiles':'assets/reelproof-android.apk.gz'},'api/semantic-download.mjs':{'includeFiles':'assets/semantic/**'}},'rewrites':[{'source':'/downloads/reelproof-android.apk','destination':'/api/android-download'},{'source':'/downloads/reelproof-semantic-models.zip','destination':'/api/semantic-download'},{'source':'/api/engine/health','destination':'https://reelproof-evidence.vercel.app/health'},{'source':'/api/engine/analyze','destination':'https://reelproof-evidence.vercel.app/v1/analyze'},{'source':'/api/engine/analyze/web','destination':'https://reelproof-evidence.vercel.app/v1/analyze/web'},{'source':'/api/engine/audio','destination':'https://reelproof-evidence.vercel.app/v1/audio'},{'source':'/api/engine/content/stream','destination':'https://reelproof-evidence.vercel.app/v1/content/stream'}],'headers':[{'source':'/(.*)','headers':[{'key':'Permissions-Policy','value':'microphone=(self), camera=(), display-capture=()'},{'key':'Referrer-Policy','value':'no-referrer'},{'key':'X-Content-Type-Options','value':'nosniff'}]},{'source':'/downloads/(.*)','headers':[{'key':'Content-Disposition','value':'attachment'}]},{'source':'/release.json','headers':[{'key':'Cache-Control','value':'no-store'}]},{'source':'/sw.js','headers':[{'key':'Cache-Control','value':'no-cache'}]},{'source':'/api/engine/(.*)','headers':[{'key':'Cache-Control','value':'no-store'}]}]}
config['headers'].append({'source':'/downloads/reelproof-ios-personal.ipa','headers':[{'key':'Content-Type','value':'application/octet-stream'},{'key':'Content-Disposition','value':'attachment; filename="reelproof-ios-personal.ipa"'}]})
(out/'vercel.json').write_text(json.dumps(config,indent=2))
manifest=[]
for path in sorted(out.rglob('*')):
 if not path.is_file():continue
 data=path.read_bytes();manifest.append({'file':str(path.relative_to(out)),'size':len(data),'sha':hashlib.sha1(data).hexdigest(),'binary':path.suffix in {'.apk','.zip','.gz','.png','.part','.ipa'}})
(root/'deployment').mkdir(exist_ok=True)
(root/'deployment/vercel-mobile.json').write_text(json.dumps({'project_id':'prj_FyO0KUHJZ4hdOCJAnwld9usEWD2X','name':'reelproof-mobile','target':'production','site_url':origin,'files':manifest},indent=2))
print(json.dumps(manifest))
