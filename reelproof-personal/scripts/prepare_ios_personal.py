"""Generate a stable, per-project iOS identity for personal-device testing.

Apple credentials are not needed to compile. The resulting device IPA still
requires development signing on the user's computer before it can be installed.
"""
import argparse,copy,hashlib,json,os,re,secrets
from pathlib import Path
import yaml

def personal_spec(base,bundle,team=''):
 if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}',bundle):raise ValueError('Invalid personal bundle ID')
 if team and not re.fullmatch(r'[A-Z0-9]{10}',team):raise ValueError('Expected a 10-character Apple Team ID')
 spec=copy.deepcopy(base);group='group.'+bundle+'.shared';extension=bundle+'.BroadcastExtension'
 spec['settings']['base'].update(CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM=team,MARKETING_VERSION='0.4.4',CURRENT_PROJECT_VERSION='7',ENABLE_DEBUG_DYLIB='NO')
 for name,identifier in [('ReelProof',bundle),('BroadcastExtension',extension)]:
  target=spec['targets'][name]
  target['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER']=identifier
  target['settings'].pop('configs',None)
  target['info']['properties']['ReelProofAppGroup']=group
  target['info']['properties']['ReelProofPersonalBuild']=True
  target['entitlements']['properties']['com.apple.security.application-groups']=[group]
  target['entitlements']['path']=name+'/'+name+'.personal.entitlements'
 spec['targets']['ReelProof']['info']['properties']['ReelProofBroadcastExtension']=extension
 spec['targets']['ReelProof']['info']['properties']['CFBundleDisplayName']='ReelProof Test'
 spec['targets']['ReelProof']['settings']['base']['INFOPLIST_KEY_CFBundleDisplayName']='ReelProof Test'
 return spec

def main():
 p=argparse.ArgumentParser();p.add_argument('--bundle');p.add_argument('--team',default='')
 p.add_argument('--ios-dir',type=Path,default=Path(__file__).resolve().parents[1]/'native/ios');a=p.parse_args()
 identity=a.ios_dir/'PersonalBuild.json'
 existing=json.loads(identity.read_text()) if identity.exists() else {}
 repository=os.environ.get('GITHUB_REPOSITORY','')
 suffix=hashlib.sha256(repository.lower().encode()).hexdigest()[:12] if repository else secrets.token_hex(6)
 bundle=a.bundle or existing.get('bundle') or 'app.reelproof.personal.p'+suffix
 spec=personal_spec(yaml.safe_load((a.ios_dir/'project.yml').read_text()),bundle,a.team)
 (a.ios_dir/'project.personal.yml').write_text(yaml.safe_dump(spec,allow_unicode=True,sort_keys=False))
 identity.write_text(json.dumps({'bundle':bundle,'app_group':spec['targets']['ReelProof']['info']['properties']['ReelProofAppGroup'],'extension':bundle+'.BroadcastExtension','requires_user_signing':True},indent=2)+'\n')
 print(json.dumps({'generated':True,'bundle':bundle,'compiled':False,'installable':False}))

if __name__=='__main__':main()
