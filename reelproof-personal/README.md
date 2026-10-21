# Windows에서 iPhone·iPad 개인 테스트 앱 설치

0.4.6은 재서명 과정에서 App Group과 공통 Keychain Sharing이 사라져도 화면 QR로 방송 확장에 연결 설정을 전달하도록 구현했습니다. 공유 저장소가 실제로 허용된 설치는 기존 경로도 유지합니다. 공유 권한을 새로 부여하거나 iOS 동의를 생략하는 방식이 아닙니다.

설치 안내: https://reelproof-mobile.vercel.app/ios-personal.html
다운로드: https://reelproof-mobile.vercel.app/downloads/reelproof-ios-personal.ipa?v=0.4.6

이 IPA는 macOS Actions에서 컴파일하며 Apple 인증서·로그인·기기 UDID·Gemini 키를 포함하지 않습니다. 임시 코드 서명은 본인 iPhone 설치용 서명이 아닙니다. Windows에서 본인 계정으로 개발용 서명해야 하며 무료 계정은 보통 7일마다 갱신해야 합니다.

## 서명·설치

1. https://sideloadly.io 에서 Windows 버전을 설치하고 공식 드라이버·Apple 소프트웨어 조건을 따릅니다.
2. iPhone을 USB로 연결하고 ‘이 컴퓨터를 신뢰’를 허용합니다.
3. IPA를 Sideloadly에 넣고 본인 Apple 계정으로 설치합니다. 갱신은 같은 계정과 Bundle ID로 합니다. 로그인·비밀번호·인증 코드는 설치 도구에서 직접 입력하고 채팅에 보내지 않습니다.
4. **앱과 ReplayKit 방송 확장을 함께 유지합니다.** QR 방식에는 App Group·공통 키체인이 필요하지 않습니다. 확장 자체를 제거하면 방송 기능을 사용할 수 없습니다.
5. iPhone이 요구하면 개발자 앱 신뢰와 설정 → 개인정보 보호 및 보안 → 개발자 모드를 확인합니다.

## 앱 연결과 방송 시작

1. 앱에 `https://reelproof-evidence.vercel.app`과 원본 검증 서버 접근 키를 입력한 뒤 **탐지 준비**를 누릅니다. Gemini 키나 `REELPROOF_APP_TOKEN_SHA256` 해시는 앱 입력값이 아닙니다.
2. 공유 저장소를 사용할 수 없으면 최대 30분의 검증 전용 세션이 발급되고 QR이 표시됩니다. 알림을 허용합니다. 세션 만료는 원본 앱 접근 키의 만료보다 늦을 수 없습니다.
3. **QR이 보이는 화면에서** 시스템 녹화 버튼 → ReelProof → 방송 시작을 누릅니다. QR을 카메라로 스캔하지 않습니다. 확장이 iOS 녹화 동의 이후 받은 영상 프레임에서 읽습니다.
4. **‘방송 연결 완료’ 알림까지 QR 화면에 머문 뒤** 릴스·쇼츠 앱으로 이동합니다. 바로 다른 앱으로 이동하면 연결하지 못할 수 있습니다. QR 수신 유효 시간은 90초이며 확장은 방송 시작 후 45초 동안 기다립니다.
5. 만료·연결 실패 시 탐지 준비부터 다시 진행합니다. 연결 키는 최대 30분 동안 유효하며 이후에는 방송을 끝내고 새로 준비합니다. 종료는 제어 센터에서 합니다.

QR에는 원본 앱 접근 키나 Gemini 키가 들어가지 않습니다. 임시 키도 유효 시간 동안 검증 권한을 가지므로 QR 화면을 공유하지 마세요. 세션은 일회용이라고 보장하지 않습니다. 고정된 프로덕션 서버에서 서명을 확인하기 전에는 화면 문자·음성을 업로드하지 않습니다. 다른 영상의 임의 서버 QR은 허용하지 않습니다.

## 빌드 재현

`.github/workflows/ios-personal.yml`은 macOS/Xcode에서 기기용 앱과 확장을 컴파일하고 QR 이미지 생성 → 2x/3x 화면 렌더링 → Vision 해독, 서명 메타데이터, iOS Simulator 준비 버튼을 검사합니다. Windows용 소스 ZIP에는 `reelproof-personal/` 폴더와 해당 경로에 맞춘 workflow가 포함됩니다.

Actions의 `ReelProof-personal-IPA-requires-your-signature` artifact 안에 실제 IPA와 `build-report.json`이 들어갑니다. 빌드 실패를 설치 성공으로 표시하지 않습니다. 같은 저장소에서는 같은 개인 Bundle ID를 사용합니다. Apple 계정이나 비밀 키 없이 컴파일하며 유료 사용 설정을 자동으로 켜지 않습니다.

## 검증 범위

실제 iPhone의 Sideloadly 재서명·QR 수신·다른 앱 화면·음성 캡처·알림은 물리 기기 확인이 별도로 필요합니다. 시뮬레이터와 QR 픽셀 테스트는 실제 ReplayKit 방송 성공의 증거가 아닙니다. 앱별 캡처 보호가 있으면 추출할 수 없습니다.

검증 원문 색인은 WHO 100개·NASA 20개·FEVER 2개입니다. Google 검색은 별도 공급자 한도를 적용받습니다. Gemini API 키는 검증 서버의 Production Secret에만 등록합니다. AI 대본 문체 알림은 실험 신호이며 영상 제작 출처나 진위 확률이 아닙니다.
