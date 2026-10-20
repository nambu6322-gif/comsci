# ReelProof personal iPhone app

The personal-device iPhone/iPad IPA compiled successfully on macOS with Xcode 16.4. The app and ReplayKit extension are both version 0.4.1 (4).

- [Download personal-test IPA](https://reelproof-mobile.vercel.app/downloads/reelproof-ios-personal.ipa)
- [Windows signing and installation guide](https://reelproof-mobile.vercel.app/ios-personal.html)
- [Successful build and artifact](https://github.com/nambu6322-gif/comsci/actions/runs/39424499293)
- [Source](reelproof-personal/)

The IPA requires development re-signing with your own Apple account on Windows, for example using Sideloadly, before installation. It is not a TestFlight build or a directly installable download. Free personal provisioning usually needs refreshing after 7 days. Actual iPhone capture, notifications and latency have not been device-tested.

Gemini API keys belong only in the evidence server's secret settings. The app uses a separately issued server access token. Without it, only the experimental on-device text-style signal runs. That signal does not establish the video's AI origin or claim truth; the current FEVER corpus contains two documents.

## Rebuild

Actions → **Build personal iPhone IPA for Windows signing** → **Run workflow**. The macOS build requires no Apple login or Gemini key. After a successful run, download the artifact and re-sign its IPA on your own computer.

IPA SHA-256: `2a28ff8ec1a7c9635dc68a9175b9ee5fdad4eac9893680b9d7f376c42350397c`

0.4.3 (6): 탐지 준비 버튼 전체의 터치 영역·즉시 상태·키보드 닫기·오류 팝업을 수정하고 알림 권한 대기와 녹화 버튼 표시를 분리했습니다. iOS Simulator UI 검사 2건이 통과했습니다. 실제 기기 서명·방송 검증은 별도입니다.

0.4.4 (7): 재서명 후 앱·방송 확장의 공통 서명 그룹을 읽고 프로필 및 실제 공유 폴더 접근을 검사합니다. 이름 변경은 처리하지만 누락된 권한을 만들지는 않습니다. 앱의 공유 권한 진단에서 원인을 복사할 수 있습니다. 실제 기기 서명·공유 권한 성공은 검증 전입니다.
