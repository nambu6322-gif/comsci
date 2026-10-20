#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$task_root/native/ios"
personal_python="${REELPROOF_BUILD_PYTHON:-python3}"
personal_simulator=$(xcrun simctl list devices available --json | "$personal_python" -c 'import json,sys; items=[d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d.get("isAvailable") and d["name"].startswith("iPhone")]; preferred=next((d for d in items if "Pro Max" in d["name"]),None); assert items,"No available iPhone simulator"; print((preferred or items[0])["udid"])')
xcodebuild -project ReelProof.xcodeproj -scheme ReelProof -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$personal_simulator" \
  -derivedDataPath build/personal-ui -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
"$personal_python" - <<'PY'
import json
from pathlib import Path
Path('personal-distribution/ui-test-status.json').write_text(json.dumps({'simulator_ui_tests_passed':True,'checks':['left and right prepare button hit areas','keyboard dismissal','invalid server alert','valid server produces next step or visible signing error'],'physical_device_tested':False},indent=2)+'\n')
PY
