#!/usr/bin/env bash
# Hosted macOS build. Contains no Apple login and no server credentials.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then echo 'macOS/Xcode is required to compile the iPhone IPA.' >&2; exit 1; fi
task_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$task_root"
personal_python="${REELPROOF_BUILD_PYTHON:-python3}"
if [[ -n "${REELPROOF_PERSONAL_BUNDLE_ID:-}" ]]; then
  "$personal_python" scripts/prepare_ios_personal.py --bundle "$REELPROOF_PERSONAL_BUNDLE_ID"
else
  "$personal_python" scripts/prepare_ios_personal.py
fi
cd native/ios
xcodegen generate --spec project.personal.yml
xcodebuild -project ReelProof.xcodeproj -scheme ReelProof -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/personal \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
personal_app='build/personal/Build/Products/Debug-iphoneos/ReelProof.app'
personal_extension="$personal_app/PlugIns/BroadcastExtension.appex"
test -d "$personal_app" && test -d "$personal_extension"
# Temporary ad-hoc code signatures preserve entitlement metadata for the user's
# re-signing tool. These are NOT Apple's paid Ad Hoc distribution signatures.
# Resolve only the public placeholder in temporary signatures. Sideloadly must
# replace the temporary prefix with the actual Apple signing team's prefix.
"$personal_python" - <<'ENTITLEMENTS'
import plistlib
from pathlib import Path
for path in [Path('ReelProof/ReelProof.personal.entitlements'),Path('BroadcastExtension/BroadcastExtension.personal.entitlements')]:
 value=plistlib.loads(path.read_bytes())
 value['keychain-access-groups']=[x.replace('$(AppIdentifierPrefix)','REELPROOF0.') for x in value['keychain-access-groups']]
 path.write_bytes(plistlib.dumps(value))
ENTITLEMENTS
codesign --force --sign - --timestamp=none --entitlements BroadcastExtension/BroadcastExtension.personal.entitlements "$personal_extension"
codesign --force --sign - --timestamp=none --entitlements ReelProof/ReelProof.personal.entitlements "$personal_app"
codesign --verify --deep --strict "$personal_app"
swiftc -swift-version 5 Shared/SigningGroups.swift "$task_root/tests/ios_signing_groups_test.swift" -o build/signing-groups-tests
build/signing-groups-tests "$personal_app"
swiftc -swift-version 5 Shared/ConnectionKeychain.swift Shared/BroadcastPairing.swift "$task_root/tests/ios_broadcast_pairing_test.swift" -o build/broadcast-pairing-tests
build/broadcast-pairing-tests
swiftc -swift-version 5 Shared/BroadcastEvents.swift "$task_root/tests/ios_broadcast_events_test.swift" -o build/broadcast-events-tests
build/broadcast-events-tests
swiftc -swift-version 5 Shared/TextModel.swift Shared/VerificationWorkQueue.swift "$task_root/tests/ios_capture_pipeline_test.swift" -o build/capture-pipeline-tests
build/capture-pipeline-tests Shared/selector-model.json
"$personal_python" - "$personal_app" <<'PY'
import json,plistlib,subprocess,sys
from pathlib import Path
app=Path(sys.argv[1]);identity=json.loads(Path('PersonalBuild.json').read_text());versions=[]
for target,bundle in [(app,identity['bundle']),(app/'PlugIns/BroadcastExtension.appex',identity['extension'])]:
 info=plistlib.loads((target/'Info.plist').read_bytes())
 assert info['CFBundleIdentifier']==bundle and info['ReelProofAppGroup']==identity['app_group']
 assert info['CFBundleSupportedPlatforms']==['iPhoneOS']
 display_name=info.get('CFBundleDisplayName')
 assert isinstance(display_name,str) and display_name.strip(), f'{target}: missing CFBundleDisplayName prevents installation'
 versions.append((info['CFBundleVersion'],info['CFBundleShortVersionString']))
 assert not list(target.glob('*.debug.dylib'))
 ent=plistlib.loads(subprocess.run(['codesign','-d','--entitlements',':-',str(target)],capture_output=True,check=True).stdout)
 assert ent['com.apple.security.application-groups']==[identity['app_group']]
 assert ent['keychain-access-groups']==['REELPROOF0.'+identity['bundle']]
assert versions[0]==versions[1]
PY
personal_stage=$(mktemp -d "${TMPDIR:-/tmp}/reelproof-personal.XXXXXX")
trap 'rm -rf -- "$personal_stage"' EXIT
mkdir -p "$personal_stage/Payload" personal-distribution
ditto "$personal_app" "$personal_stage/Payload/ReelProof.app"
personal_ipa="$PWD/personal-distribution/ReelProof-personal-resign-required.ipa"
ditto -c -k --keepParent "$personal_stage/Payload" "$personal_ipa"
"$personal_python" - "$personal_ipa" <<'PY'
import hashlib,json,plistlib,sys,zipfile
from pathlib import Path
path=Path(sys.argv[1]);root=Path.cwd()
with zipfile.ZipFile(path) as archive:
 assert archive.testzip() is None
 assert 'Payload/ReelProof.app/Info.plist' in archive.namelist()
 assert 'Payload/ReelProof.app/PlugIns/BroadcastExtension.appex/Info.plist' in archive.namelist()
 bundles=[]
 for name in ['Payload/ReelProof.app/Info.plist','Payload/ReelProof.app/PlugIns/BroadcastExtension.appex/Info.plist']:
  info=plistlib.loads(archive.read(name));display_name=info.get('CFBundleDisplayName')
  assert isinstance(display_name,str) and display_name.strip(), f'{name}: missing CFBundleDisplayName in packaged IPA'
  bundles.append({key:info[key] for key in ['CFBundleIdentifier','CFBundleDisplayName','CFBundleVersion','CFBundleShortVersionString']})
report={'compiled':True,'signature':'temporary ad-hoc; user development signing required','signed_for_device':False,'installable_by_direct_download':False,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,'identity':json.loads((root/'PersonalBuild.json').read_text()),'bundles':bundles,'signing_group_resolution_tests_passed':True,'shared_keychain_entitlements_verified':True,'qr_pairing_pixel_tests_passed':True,'qr_pairing_requires_shared_entitlements':False,'darwin_cross_process_status_tests_passed':True,'capture_pipeline_regression_tests_passed':True,'physical_device_tested':False}
(path.parent/'build-report.json').write_text(json.dumps(report,indent=2)+'\n')
PY
echo 'IPA compiled. It must be re-signed on Windows/Mac with your own Apple account before installation.'
