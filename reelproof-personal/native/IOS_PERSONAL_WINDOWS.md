# Windows에서 본인 iPhone·iPad에 설치하는 개인 테스트

2026년 10월 20일 macOS Actions에서 **개인 테스트 IPA 빌드에 성공했습니다.**
0.4.4는 재서명된 앱과 방송 확장의 서명에서 공통 App Group을 읽고,
프로필 및 실제 공유 폴더 접근 허용을 확인합니다. 이름만 바뀐 경우를 처리하고,
서명 권한이 없으면 진행하지 않습니다. 앱의 ‘공유 권한 진단 → 권한 진단 복사’에
권한 누락·불일치·프로필 불허·폴더 접근 거부를 구분해 표시합니다.
서버 키·Apple 계정·기기 UDID는 진단에 포함하지 않습니다.
앱과 방송 확장의 표시 이름·버전·App Group·ARM64 기기 실행 파일과 ZIP 무결성을
확인했습니다. 실제 기기의 Apple 개발용 서명·설치·동작 검증은 아직입니다.

다운로드: https://reelproof-mobile.vercel.app/downloads/reelproof-ios-personal.ipa
빌드: https://github.com/nambu6322-gif/comsci/actions/runs/39424499293

## 만드는 앱

유료 TestFlight 없이 본인의 무료 Apple 계정으로 개발용 서명·설치를 하는
방법입니다. 앱 본체와 ReplayKit 방송 확장을 유지합니다. 시스템 화면 방송을
시작한 뒤 다른 앱으로 이동하면 화면 OCR과 허용된 재생 음성을 처리하도록
구성되어 있습니다. 실제 iPhone의 앱별 캡처 허용·알림·성능은 검증 전입니다.

Apple 공식 지원표는 무료 Apple Developer 계정에도 App Groups를 지원하는
것으로 표시합니다. 실제 발급된 프로필과 재서명 도구가 앱·확장의 동일한
App Group을 유지하는지는 설치 때 확인해야 합니다. 권한을 읽지 못하면 앱과
확장이 설명을 표시하고 방송 시작을 중단합니다.

공식 지원표: https://developer.apple.com/help/account/reference/supported-capabilities-ios
무료 계정·7일 유효기간: https://developer.apple.com/help/account/basics/about-your-developer-account

## 1. GitHub macOS runner에서 IPA 만들기

`.github/workflows/ios-personal.yml`을 GitHub 저장소에 등록하고 Actions에서
**Build personal iPhone IPA for Windows signing → Run workflow**를 실행합니다.
Apple 계정, 인증서, Gemini API 키 없이 기기용 앱을 컴파일합니다. 무료 GitHub
계정도 저장소 유형과 남은 Actions 할당량에 따라 사용 가능하며, 유료 사용이나
결제 설정을 자동으로 켜지 않습니다.

성공하면 `ReelProof-personal-IPA-requires-your-signature` artifact를 내려받아
압축을 해제하세요. 내부의 `ReelProof-personal-resign-required.ipa`는 Windows에서
본인의 개발용 서명을 받아야 합니다. 임시 코드 서명만 포함되어 있으며,
웹사이트에서 내려받는 것만으로 설치할 수 있는 파일이 아닙니다. 유료 Apple
프로그램의 Ad Hoc 배포 서명과도 다릅니다.

`build-report.json`에는 실제 생성 파일의 SHA-256과 빌드 여부를 기록합니다.
빌드 실패 시 IPA라고 표시하거나 설치 링크를 생성하지 않습니다.
같은 저장소는 같은 Bundle ID를 생성하므로 갱신할 때 불필요하게 새 App ID를
소모하지 않습니다. 외부 저장소에 하위 폴더로 제공하는 설치 준비 ZIP에는
`reelproof-personal/` 폴더와 전용 workflow가 포함됩니다.

## 2. Windows에서 서명·설치

1. Sideloadly 공식 사이트 https://sideloadly.io 에서 Windows 버전을 설치합니다.
   Windows 드라이버·Apple 소프트웨어 요구 사항은 해당 사이트 안내를 따릅니다.
2. iPhone을 USB로 연결하고 ‘이 컴퓨터를 신뢰’를 허용합니다.
3. 빌드된 IPA를 Sideloadly에 넣고 본인 Apple 계정으로 로그인해 설치합니다.
   로그인·2단계 인증은 Windows 도구에서 직접 수행하며 채팅에 보내지 않습니다.
4. 방송 확장을 제거하지 마세요. App Group은 앱·확장의 서명과 프로필 모두에서
   허용되어야 합니다. Sideloadly의 사용자 정의 권한 기능에는 유료 계정 등의
   조건이 있으므로 무료 기본 설치에서 권한 유지를 보장하지 않습니다.
   공식 기록: https://sideloadly.io/changelog
   오류가 나면 ‘공유 권한 진단’을 확인하세요. 서명 그룹 ‘없음’은 파일 재설치만으로
   해결되지 않습니다. Windows의 다른 서명 경로로 AltStore Classic·AltServer를
   검토할 수 있습니다. 이 경로의 실기기 성공을 검증한 것은 아닙니다.
   공식 설치: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
5. 기기가 요구하면 설정에서 개발자 앱을 신뢰하고 개발자 모드를 활성화합니다.
   개발자 모드는 보통 설정 → 개인정보 보호 및 보안 → 개발자 모드에 있습니다.
6. 앱을 열어 별도 발급받은 `rp_ios_`로 시작하는 검증 서버 접근 키를 입력하고 ‘탐지 준비’를 누릅니다. 알림을
   허용한 뒤 시스템 방송 버튼에서 ReelProof를 선택하고 릴스 앱으로 이동합니다.
   종료는 제어 센터에서 화면 방송을 중단합니다.
   Vercel의 `REELPROOF_APP_TOKEN_SHA256` 값은 인증용 해시이므로 앱에 입력하지 않습니다.
   버튼을 눌렀을 때 공유 권한 오류가 나오면 해당 문구를 확인해야 하며 방송을 시작하지 않습니다.

무료 계정의 개발용 설치는 보통 7일 뒤 만료됩니다. 같은 파일·계정으로
재서명해 갱신해야 합니다. IPA를 실제 만들고 서명해 설치하는 단계를 거치기
전에는 개인 기기에서 동작한다고 보장하지 않습니다.

## Gemini와 검증 서버

새 Gemini API 키는 앱에 넣지 않고 Vercel의 `reelproof-evidence` 프로젝트에서
민감한 환경변수 `GEMINI_API_KEY`에 등록합니다. 변경된 키를 반영하는 서버
재배포와 실제 생성·음성 전사 호출이 필요합니다. 같은 Google 프로젝트의 키는
할당량을 공유할 수 있습니다. 앱에는 별도 발급한 검증 서버 접근 키를 입력합니다.

현재 자료 범위는 FEVER 원문 2개입니다. AI 대본 문체 점수는 텍스트 실험
신호이며, 영상의 AI 제작 여부나 진위 확률이 아닙니다. 서버 연결·권한·실기기
검증 없이 자동 탐지가 완료되었다고 표시하지 않습니다.


## 0.4.5 공유 설정 수정

App Group 폴더를 사용할 수 없으면 두 대상의 공통 서명 keychain-access-groups로 연결 정보를 저장합니다. 탐지 준비에서 SecItem 쓰기·읽기를 실제로 확인합니다. Sideloadly에서 확장을 제거하지 말고 Keychain Sharing을 유지하세요. 앱과 확장 모두에 동일한 실제 팀 접두사가 적용되어야 합니다. 공유 키체인까지 제거된 서명은 코드로 권한을 추가할 수 없습니다. 이 경우 연결 권한 진단에 그룹과 OSStatus가 표시됩니다. 서버 키나 방송 내용을 진단 복사에 포함하지 않습니다.
