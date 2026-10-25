#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$task_root/native/ios"
personal_python="${REELPROOF_BUILD_PYTHON:-python3}"
personal_simulator=$(xcrun simctl list devices available --json | "$personal_python" -c 'import json,sys; items=[d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d.get("isAvailable") and d["name"].startswith("iPhone")]; preferred=next((d for d in items if "Pro Max" in d["name"]),None); assert items,"No available iPhone simulator"; print((preferred or items[0])["udid"])')
"$personal_python" - "$personal_simulator" <<'PY'
import subprocess,sys
device=sys.argv[1]
subprocess.run(['xcrun','simctl','boot',device],check=False,timeout=45)
subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],check=True,timeout=180)
PY
xcodebuild -project ReelProof.xcodeproj -scheme ReelProof -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$personal_simulator" \
  -derivedDataPath build/personal-ui -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 90 -destination-timeout 60 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test 2>&1 | tee build/personal-ui-test.log
"$personal_python" - <<'PY'
import json
from pathlib import Path
Path('personal-distribution/ui-test-status.json').write_text(json.dumps({'simulator_ui_tests_passed':True,'simulator_picker_action_tests_passed':True,'content_link_ui_tests_passed':True,'checks':['link entry and invalid URL feedback without a network request','left and right prepare button hit areas','keyboard dismissal','invalid server alert','missing key cannot open broadcast or show detecting','picker action waits for window and opens once per prepare request','unsupported picker hierarchy preserves manual fallback'],'physical_system_consent_ui_tested':False,'physical_device_tested':False},indent=2)+'\n')
PY
