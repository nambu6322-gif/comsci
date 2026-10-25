## 영상·뉴스 기사 링크 입력 · 0.5.0

인증된 `POST /v1/content/stream`에 `{"url":"https://…","start_seconds":35,"duration_seconds":60}`을 보냅니다. `start_seconds`는 선택 사항이며 유튜브에 적용합니다. 앱 UI는 60초 구간을 사용하고 API는 30~120초를 허용합니다. 기사는 공개 본문 최대 24,000자에서 원문에 실제 있는 인용문을 최대 3개 선별합니다. 유튜브는 Gemini의 공개 YouTube URL 영상 읽기로 선택 구간을 전사합니다. 제목·설명만으로 내용을 만들어 내거나 공식 자막을 내려받았다고 표시하지 않습니다.

응답은 NDJSON이며 `content`(출처·추출 범위·주장), `result`(완료된 개별 주장), `claim_error`(그 주장만 미완료), `done` 순서입니다. 추출 실패·전체 연결 오류는 `error`로 반환합니다. 한 주장의 공급자 실패로 다른 주장 검증을 취소하지 않습니다. `claim_error`는 진위 판정이 아닙니다. 기존 텍스트·음성 API는 유지합니다.

입력 기사·영상 자체는 원문 색인에 넣지 않으며, 같은 입력 URL은 대조 근거에서 제외합니다. 추적 매개변수와 BBC의 도메인 별칭도 비교합니다. 별도 대조 자료가 없으면 근거 부족이고, 필요한 Google 검색이 공급자 한도에 걸리면 그 주장은 미완료입니다. 검색 요금·한도는 자동 변경하지 않습니다. 비공개 영상·로그인/유료/차단 기사·삭제 자료는 읽지 못할 수 있으며 우회하지 않습니다. 현재 기사 링크 읽기는 `content_input.article_allowed_url()`에 정의한 공개 출처와 네이버·다음·네이트 뉴스 도메인을 사용합니다.

유튜브는 선택 구간, 기사는 표시한 본문 범위 안의 최대 3개 주장을 확인하며 영상·기사 전체의 진위를 보장하지 않습니다. 실시간 화면·앱 음성은 기존 ReplayKit 동의 경로를 사용합니다. 원문 벡터 검색은 기존 C 순차탐색을 유지합니다.

재현 검사: `python tests/content_input_test.py`, `node tests/content_stream.test.mjs`, `python tests/content_browser_test.py`. 공식 영상 입력 문서: https://ai.google.dev/gemini-api/docs/video-understanding

# Gemini / OpenAI + FEVER LightRAG 검증 서버

운영 기본 공급자는 Gemini입니다. 현재 설정은 `GEMINI_MODEL=gemini-3.5-flash-lite`, `GEMINI_EMBEDDING_MODEL=gemini-embedding-001`, `GEMINI_FALLBACK_MODEL=off`입니다. 계정의 실제 모델 목록에 있는 Flash Lite를 사용하며 시간 초과가 관측된 3.8·3.7을 자동으로 다시 호출하지 않습니다. `LLM_PROVIDER=gemini`에서는 Gemini 생성·임베딩·전사만 호출합니다. Gemini 색인도 공급자·임베딩 모델별 하위 디렉터리에 분리합니다. OpenAI API 크레딧 미충전 확인 뒤 사용자가 Gemini 복귀를 요청했습니다.

선택적으로 `LLM_PROVIDER=openai`를 설정하면 OpenAI 경로를 사용할 수 있습니다. 이때 API 크레딧과 사용 한도 설정이 필요합니다. Vercel **reelproof-evidence** 프로젝트의 Production Secret에 `OPENAI_API_KEY`를 등록합니다. 휴대폰에는 기존 앱 전용 접근 키를 넣습니다. OpenAI 키를 앱·브라우저·공개 소스·채팅에 넣지 않습니다. 변경한 Secret은 새 배포부터 반영됩니다.

기본 모델은 `OPENAI_MODEL=gpt-6-luna`, 임베딩은 `OPENAI_EMBEDDING_MODEL=text-embedding-3-small`(768차원), 음성 전사는 `OPENAI_TRANSCRIPTION_MODEL=gpt-transcribe`입니다. 2026-10-20 공식 모델·API 문서를 확인한 ID이며 계정의 실제 접근 가능 여부는 임베딩·판정 실호출로 검사합니다. 불필요한 Models Read 권한을 요구하지 않습니다. 모델 설정값은 서버 환경변수로 변경할 수 있습니다. API 결제·잔액·사용 한도는 OpenAI API 프로젝트의 설정을 따릅니다.

텍스트 검증은 LightRAG의 `naive` 원문 벡터 검색 뒤 OpenAI Responses API의 엄격한 JSON Schema 출력을 사용합니다. `store=false`, 자동 재시도 없음, GPT-6의 추론량 low, 출력 상한 2,048 토큰입니다. 기존 원문 인용 검사는 그대로 적용하며, 반환된 인용이 실제 검색 원문에 없으면 SUPPORTS/REFUTES를 승인하지 않습니다. 공급자 오류·잔액 부족·불완전한 응답은 판정 성공으로 표시하지 않습니다.

OpenAI 색인은 공급자·임베딩 모델·차원·원문 해시별 별도 디렉터리에 만듭니다. Gemini 벡터 스냅샷을 복사하거나 차원만 같다는 이유로 재사용하지 않습니다. 현재 OpenAI 경로는 원문 청크 벡터 검색이며 지식 그래프 검색은 사용하지 않습니다. LightRAG `ainsert_custom_kg`의 chunks 입력만 사용하여 개체·관계를 만들어 내지 않고 색인합니다. 원문은 `data/`에 출처가 보존된 자료이며, 현재 WHO 100개·NASA 20개·FEVER 위키 2개입니다. 생성 모델을 바꾸어도 사실 확인 자료 범위나 측정 정확도가 늘어나는 것은 아닙니다.

서버의 첫 기동에서 원문 청크 임베딩을 만들며 임시 디스크 인스턴스가 새로 생기면 다시 계산될 수 있습니다. 장기 운용 시 공급자별 색인을 영구 스토리지에 보존하세요. 전체 초기화 55초, 텍스트 요청 38초, 검색 12초, 판정 26초로 제한합니다. 음성 입력은 별도 전사 시간이 추가됩니다. API는 기존 `/health`, `/v1/analyze`, `/v1/audio`, `/v1/style` 형식을 유지합니다. 모델 변경을 위해 iOS IPA를 다시 설치할 필요는 없습니다.

준비 완료는 인증·색인이 끝났다는 뜻이며 실제 판정 성공과 구분합니다. `/health`는 provider, embedding_model, generation_status, last_generation_model을 반환합니다. 키 원문은 반환하지 않습니다. 앱 키는 관리자 진단 접근을 허용하지 않습니다.

공식 문서: https://developers.openai.com/api/docs/models/gpt-6-luna · https://developers.openai.com/api/docs/guides/structured-outputs · https://developers.openai.com/api/docs/guides/embeddings · https://developers.openai.com/api/docs/guides/speech-to-text

아래는 Gemini 운영 당시의 이전 기록이며, 명시적으로 `LLM_PROVIDER=gemini`를 선택했을 때만 해당합니다.

# Gemini + FEVER LightRAG 검증 서버

Gemini API 키는 채팅·Git·앱 번들에 넣지 않습니다. 배포 서비스의 Secret Manager/환경 변수에 GEMINI_API_KEY와 실제 GEMINI_MODEL ID를 등록하세요. 서버 시작 시 Gemini 모델 목록에서 해당 ID를 확인합니다. 구독 상품명이나 표시 이름만으로 API 모델 ID를 추정하지 않습니다.

REELPROOF_TOKEN은 휴대폰 앱이 이 검증 서버에 접근하는 별도 비밀입니다. 사용자별 인증이 필요한 공개 서비스에서는 이 단일 연구용 토큰 대신 적절한 기기별 세션을 적용해야 합니다.

FEVER 공식 위키 원문을 data/ 아래 TXT로 준비하세요. 상위 research/prepare_fever.py가 원문 문서·문장 번호·출처를 보존해 변환합니다. FEVER의 claim/label 목록 자체를 사실 자료로 색인하면 안 됩니다. 모델 가중치는 기존의 사전 학습 TF-IDF 로지스틱 선별 기준을 사용합니다.

환경 변수와 원문이 있으면 초기화 과정에서 실제 LightRAG로 임베딩·개체·관계 추출과 색인을 수행합니다. 비용이 발생할 수 있는 Gemini API 작업입니다. rag_storage를 영구 디스크에 보존하면 내용 해시로 이미 등록한 문서를 건너뜁니다. 키·모델·접근 토큰·원문이 없으면 /health는 ready=false이며, 미준비 상태를 완료로 표시하지 않습니다.

`docker compose up --build -d` 이후 HTTPS reverse proxy 뒤에서 서비스하세요. Compose 기본 바인딩은 127.0.0.1:8080입니다. 무인으로 공개 키를 생성하거나 서버 요금제에 가입하지 않습니다. Vercel 프로젝트 reelproof-evidence를 만들었습니다. 사용자의 명시적 동의를 받은 뒤 Gemini 키와 서버 접근 키를 Vercel production Secret으로 등록했습니다. SSO 변경 없이 외부 /health=200 ready=false, 비인증 분석=401을 확인했습니다. 키가 없으면 외부 서버의 /health는 ready=false여야 합니다.

API: GET /health (비밀 미포함), POST /v1/analyze (JSON text), POST /v1/audio (짧은 WAV/MP4 바이트). 보호된 요청에는 `Authorization: Bearer <REELPROOF_TOKEN>`을 사용합니다. 텍스트 길이는 12,000자, 오디오 입력은 2.5MB 이하입니다. ASR은 Gemini 오디오 입력을 사용합니다. 음성 인식과 근거 검증 API 호출 시간이 모두 포함되므로 화면 OCR만 사용하는 경로보다 느릴 수 있습니다.

추가 API `POST /v1/style`은 같은 인증과 JSON text 형식을 사용하고, 새 한국어 생성문 TF-IDF 모델만 실행합니다. Gemini를 호출하지 않으므로 공급자 할당량 중단 중에도 문체 신호를 반환할 수 있습니다. 이 응답의 사실 verdict는 항상 NOT_ENOUGH_INFO, 영상 제작 판정은 UNAVAILABLE입니다. 문체 점수를 사실 확률로 전환하지 않습니다. 새 모델은 KatFish 문서 시험 92.6%·처음 240자 시험 85.6%였으며 실제 릴스·AI 영상 성능은 평가하지 않았습니다. 이 신호는 기존 모델 점수와 별도로 반환합니다.

실측 검증: 모델이 없는 상태의 readiness, 권한 검사, 실제 설치한 LightRAG의 API 형식, 원문 인용 검사 테스트를 수행합니다. 초기 연결 시험에서는 실제 Gemini 생성·임베딩과 FEVER 원문 2개 색인 및 일치·반박 질의를 확인했습니다. 실제 호출 질의 2건은 약 8–11초였고 반복 호출은 캐시를 사용할 수 있습니다. 이 수치는 휴대폰 추출·음성 인식 지연을 포함하지 않습니다. corpus가 매우 작고 FEVER는 2017년 영문 위키 자료이므로 최신 한국어 릴스의 일반적인 사실 검증 성능을 입증하지 않습니다.

청크 길이와 문맥 예산은 외부 토크나이저 다운로드 없이 보수적인 UTF-8 바이트 예산으로 계산합니다. 이는 Gemini의 실제 토큰 수가 아닙니다. Unicode 경계에서 원문이 손실되지 않도록 코드 포인트와 패딩으로 표현하며 테스트로 왕복·분할 복원을 확인합니다.

클라우드에는 공개 원문 기반 index_snapshot을 함께 배포합니다. 각 인스턴스는 이 읽기 전용 스냅샷을 임시 디스크로 복사하며 실행 중 캐시는 영구 보존하지 않습니다. 자료 갱신은 별도의 색인 준비 후 새 스냅샷으로 재배포해야 합니다.

직접 입력(source=manual 또는 safari-web)은 사용자의 명시적 검증 요청이므로 선별 점수와 관계없이 검색합니다. 화면·오디오 자동 추출은 기존 TF-IDF 임계값 0.50을 적용합니다. 별도 앱 연결 토큰은 서버 접근 키로 서명하며 analyze 범위와 만료 시각을 검사합니다. 개인 연결 파일은 공개 배포물에 포함하지 않습니다.

2026-10-19: 클라우드 키 등록과 FEVER 색인 초기화는 성공했습니다. Gemini generateContent/Interactions 실호출에서 공급자 503(high demand)을 확인하여 현재 실제 판정 검증은 외부 서비스 응답 대기 상태입니다. 공급자 실패 직후 /health는 generation_status=unavailable을 반환하며 근거 판정을 성공으로 표시하지 않습니다. 60초 후 재시도를 허용합니다. 기본 대체 모델은 설정하지 않으며, 이미 사용이 중단된 모델로 자동 전환하지 않습니다.

추가 확인: Gemini 무료 요청 한도 20회 초과(429)가 반환되었습니다. 공급자 재시도 시각을 GEMINI_QUOTA_RETRY_AT에 등록해 그 전에는 음성·판정 생성 요청을 보내지 않습니다. 결제 설정을 사용자가 변경해 한도가 증가한 경우에는 이 일시 중지 변수를 해제한 뒤 재배포해야 합니다. 결제는 자동 변경하지 않았습니다.

## 개인 테스트 앱 전용 접근 키

앱 전용 키는 `/v1/analyze`, `/v1/audio`, `/v1/style`에서만 사용합니다.
서버에는 원문 대신 SHA-256 해시를 `REELPROOF_APP_TOKEN_SHA256`에 저장하고,
Unix 만료 시각을 `REELPROOF_APP_TOKEN_EXPIRES_AT`에 설정합니다. 두 값이
유효해야 인증됩니다. 원문 키는 사용자의 앱에만 입력하고 저장소·IPA·공개
다운로드에 넣지 않습니다. 이 키는 관리자 진단에 접근할 수 없습니다.
기존 `REELPROOF_TOKEN`과 그 키로 발급한 기기 토큰은 유지됩니다.
변경된 환경변수는 운영 서버를 재배포해야 반영됩니다.

2026-10-20 응답 시간 개선: 웹 텍스트 검증은 LightRAG의 `naive` 원문 벡터 검색(`aquery_data`) 후 구조화된 Gemini 판정 한 번을 사용합니다. Flash의 추론량은 low, 출력 한도는 2,048 토큰입니다. minimal은 해당 API의 400 응답이 확인되어 사용하지 않습니다. 기존 `mix`의 LLM 키워드 추출·그래프 요약 단계를 텍스트 검증 경로에서 제거했습니다. 별도 KG 데이터와 색인은 유지되지만 이 경로는 그래프 검색을 사용하지 않습니다. 검색 12초, 판정 단일 호출 26초, 대기열 3초, 텍스트 요청 전체 38초 제한으로 실패 단계를 구분합니다. Gemini SDK의 자동 3회 재시도를 제거했습니다. 원문에 정확히 포함된 인용만 승인하며, 공급자 장애를 근거 부족 성공으로 바꾸지 않습니다. 이는 정확도 향상 학습이 아니며 운영 성능은 실제 배포 검사 결과를 참고하세요.

503 장애 대체: 계정의 실제 모델 목록에서 텍스트 Flash 3 계열을 확인한 경우에만 대체 모델 하나를 선택합니다. 명시한 GEMINI_FALLBACK_MODEL이 있으면 그 목록을 우선합니다. 500/502/503/504 또는 시간 초과에 한해서 한 번 대체하며, 인증·설정·한도 오류는 다른 모델로 재시도하지 않습니다. 대체 가능 시 첫 모델 6초·대체 모델 26초 (전체 38초 안에서)로 제한하고, 사용 가능한 3 계열의 안정 버전을 우선합니다. gemini-2.5-flash는 목록에 표시되더라도 실제 생성에서 404가 확인되어 자동 선택에서 제외했습니다. /health의 verification_models와 last_generation_model로 실제 경로를 구분합니다. 모델 변경을 정확도 향상으로 해석하지 않습니다.

웹앱의 녹음·음성 파일은 `/v1/audio?source=safari-web`로 직접 확인을 요청합니다. 텍스트 직접 입력과 마찬가지로 TF-IDF 선별 임계값 때문에 명시적 확인 요청을 버리지 않습니다. 네이티브 자동 추출은 쿼리 없이 기존 선별 임계값을 유지합니다. 음성 전체 요청은 웹 수동 입력 52초·자동 추출 40초로 제한합니다.


## 원문 확장 및 최신 웹 근거

고정 검색 원문은 FEVER 2개, WHO 100개, NASA 20개로 확장했습니다. WHO와 NASA의 이용 조건은 data/source-manifest.json과 각 문서에 보존합니다. 이 작업은 모델 추가 학습이 아니라 원문 검색 색인 확장입니다.

Gemini는 google_search 도구로 사건 근거를 찾습니다. 사망·화재·최신 시점의 사건은 /v1/analyze에서 웹 경로로 보내며, /v1/analyze/web는 명시적 웹 검색용입니다. 검색 결과의 요약은 근거로 색인하지 않습니다. 공개 HTTPS 원문에 대해 도메인·주소·리디렉션 검사를 거친 뒤 실제 읽은 본문에 있는 정확한 인용만 반환합니다. 발행일·대상·부정 표현·소문 인용 여부를 판정에 포함합니다. 검색 실패는 서비스 오류 또는 판별 불가이며 거짓이 아닙니다.

WEB_SEARCH_ENABLED=0은 자동 사건 검색을 끕니다. Google 검색에는 모델 생성과 별도 사용량 한도/요금이 적용될 수 있습니다. 원문 122개나 검색 연결 자체는 실제 릴스 정확도 평가를 의미하지 않습니다. 추가 검색·원문 읽기 과정 때문에 기존 고정 자료 질의보다 시간이 더 걸릴 수 있으며, 클라이언트 요청 기한도 이를 허용합니다.

### iPhone 화면 QR 세션 (0.4.6)

`POST /v1/device-session`은 기존 원본 앱 접근 키 또는 서버 관리 키로 인증한 뒤 최대 30분의 `aud=reelproof`, `scope=analyze` HMAC 세션을 발급합니다. 발급된 세션의 만료는 부모 앱 키의 만료보다 늦을 수 없습니다. `GET /v1/device-session`은 이 세션의 서명을 확인하며 AI 모델을 호출하지 않습니다. 두 응답은 `Cache-Control: no-store`입니다. 세션은 추가 세션 발급과 관리자 API에 사용할 수 없습니다.

iPhone 호스트 앱은 원본 키 대신 세션을 QR에 넣습니다. 방송 확장은 ReplayKit 동의 이후 최초 화면에서 QR을 읽고, 고정된 프로덕션 서버가 서명을 확인한 뒤에만 OCR·음성 업로드를 시작합니다. QR을 읽는 시간은 90초로 제한하며 임시 키도 공유하지 않아야 합니다. 세션은 일회용 토큰이 아니며, 실제 기기의 방송·알림 검증은 별도로 필요합니다. 공유 저장소가 허용된 설치의 기존 경로는 유지합니다.
