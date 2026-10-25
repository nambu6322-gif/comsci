"""Prepare public deployment files while preserving original UTF-8 bytes. Large indexed files need uploading by the emitted SHA-1 references."""
import argparse,json,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output-dir',type=Path,required=True);args=p.parse_args()
r=Path(__file__).resolve().parents[1];w=args.output_dir;w.mkdir(parents=True,exist_ok=True);files=[];uploads=[]
for folder in ['models','index_snapshot','data']:
 for p in sorted((r/'backend'/folder).glob('*')):
  if not p.is_file() or p.suffix not in ['.txt','.json','.graphml','.md']:continue
  name=str(p.relative_to(r/'backend'));data=p.read_bytes()
  if folder=='models' or (folder=='index_snapshot' and len(data)>100000):
   f={'file':name,'sha':hashlib.sha1(data).hexdigest(),'size':len(data)};files.append(f)
   if folder=='index_snapshot':uploads.append({'path':str(p),'bytes':len(data),'sha':f['sha']})
  else:files.append({'file':name,'data':p.read_bytes().decode('utf-8'),'encoding':'utf-8'})
for name in ['app.py','knowledge_judgment.py','provider_requests.py','content_input.py','sequential_search.py','sequential_search.c','sequential_search.h','build_c_search.py','openai_backend.py','web_evidence.py','requirements.txt','pyproject.toml','vercel.json']:files.append({'file':name,'data':(r/'backend'/name).read_bytes().decode('utf-8'),'encoding':'utf-8'})
marker=set(json.loads((r/'backend/index_snapshot/reelproof-docs.json').read_text()))
for entry in files:
 if entry['file'].startswith('data/') and entry['file'].endswith('.txt'):
  if hashlib.sha256(entry['data'].encode('utf-8')).hexdigest() not in marker:raise ValueError('Prepared source hash mismatch: '+entry['file'])
(w/'backend-files.json').write_text(json.dumps(files));(w/'backend-uploads.json').write_text(json.dumps(uploads));print(json.dumps({'files':len(files),'payload_bytes':(w/'backend-files.json').stat().st_size,'new_uploads':uploads}))
