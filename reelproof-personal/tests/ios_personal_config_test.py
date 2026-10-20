"""Offline personal-build checks; Xcode/device signing is a separate step."""
import importlib.util,json,os,subprocess,tempfile
from pathlib import Path
import yaml

root=Path(__file__).resolve().parents[1]
loader=importlib.util.spec_from_file_location('personal',root/'scripts/prepare_ios_personal.py');module=importlib.util.module_from_spec(loader);loader.loader.exec_module(module)
base=yaml.safe_load((root/'native/ios/project.yml').read_text())
bundle='app.reelproof.personal.test123';spec=module.personal_spec(base,bundle)
assert base['targets']['ReelProof']['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER']=='app.reelproof.ios'
assert spec['settings']['base']['CODE_SIGN_STYLE']=='Automatic'
assert spec['settings']['base']['DEVELOPMENT_TEAM']==''
assert spec['targets']['ReelProof']['dependencies']==[{'target':'BroadcastExtension','embed':True}]
for name,identifier in [('ReelProof',bundle),('BroadcastExtension',bundle+'.BroadcastExtension')]:
 target=spec['targets'][name];assert target['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER']==identifier
 assert target['entitlements']['properties']['com.apple.security.application-groups']==['group.'+bundle+'.shared']
 assert target['info']['properties']['ReelProofAppGroup']=='group.'+bundle+'.shared'
 assert 'PROVISIONING_PROFILE_SPECIFIER' not in str(target)
assert spec['targets']['ReelProof']['info']['properties']['ReelProofBroadcastExtension']==bundle+'.BroadcastExtension'
for invalid in ['bad','app.reelproof;echo test','../invalid.bundle.id']:
 try:module.personal_spec(base,invalid)
 except ValueError:pass
 else:raise AssertionError('Accepted invalid bundle ID')
with tempfile.TemporaryDirectory() as directory:
 d=Path(directory);(d/'project.yml').write_text(yaml.safe_dump(base))
 cmd=['python',str(root/'scripts/prepare_ios_personal.py'),'--ios-dir',str(d)]
 first=subprocess.run(cmd,capture_output=True,text=True,check=True);identity=json.loads((d/'PersonalBuild.json').read_text())
 second=subprocess.run(cmd,capture_output=True,text=True,check=True)
 assert json.loads((d/'PersonalBuild.json').read_text())==identity
 assert json.loads(first.stdout)['bundle']==json.loads(second.stdout)['bundle']
 assert json.loads(first.stdout)['installable'] is False
with tempfile.TemporaryDirectory() as directory:
 d=Path(directory);(d/'project.yml').write_text(yaml.safe_dump(base))
 cmd=['python',str(root/'scripts/prepare_ios_personal.py'),'--ios-dir',str(d)]
 environment=dict(os.environ,GITHUB_REPOSITORY='test-owner/reelproof')
 first=json.loads(subprocess.run(cmd,capture_output=True,text=True,check=True,env=environment).stdout)['bundle']
 (d/'PersonalBuild.json').unlink()
 second=json.loads(subprocess.run(cmd,capture_output=True,text=True,check=True,env=environment).stdout)['bundle']
 assert first==second
print('PASS personal config: stable unique IDs, matching app/extension App Group, automatic development signing, preserved broadcast extension, no Apple login or provider secrets required to prepare.')
