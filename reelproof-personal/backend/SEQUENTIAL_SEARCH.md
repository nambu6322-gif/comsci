# ReelProof C 순차탐색 위치

핵심 알고리즘은 **`backend/sequential_search.c`의 `rp_sequential_search()`** 입니다.

```c
for (size_t row = 0; row < row_count; ++row) {
    double dot_product = 0.0;
    for (size_t d = 0; d < dimensions; ++d)
        dot_product += (double)vectors[row * dimensions + d] * normalized[d];
    /* 임계값을 확인하고 상위 k개 결과를 유지합니다. */
}
```

저장된 원문 조각의 벡터를 처음부터 끝까지 하나씩 비교합니다. 조회 벡터는 C에서 정규화하며, 저장된 벡터는 LightRAG/NanoVectorDB가 이미 정규화한 것을 사용합니다. 유사도가 임계값 이상인 결과 중 최대 4개를 유지합니다. 처음 발견한 결과에서 멈추지 않으며, 동점이면 저장 순서를 따릅니다.

- `backend/sequential_search.h`: C 함수의 입력·출력 선언.
- `backend/sequential_search.py`: NumPy 배열을 연속된 float32 버퍼로 준비하고 `ctypes`로 C 함수를 호출하는 연결 코드. Python으로 탐색하는 대체 경로는 없습니다.
- `backend/build_c_search.py`: 배포 대상에서 C를 공유 라이브러리로 컴파일합니다. Vercel은 `pyproject.toml`의 build 설정으로 배포 전에 실행하고, `vercel.json`의 includeFiles 설정으로 생성된 라이브러리를 포함합니다. 실행 중에 컴파일하지 않습니다.
- `backend/app.py`의 `initialize()` → `install_sequential_search(rag)`: LightRAG에 연결하는 부분. `verify_claim()`은 `mode='naive', chunk_top_k=4`로 원문을 요청합니다.

전체 흐름: **주장 → 임베딩 → C 순차탐색 → 최대 4개 원문 → Gemini 원문 대조 → 주장별 알림**. FastAPI 서버와 LightRAG는 Python이며, 검색 알고리즘을 C로 구현했습니다. 최신 사건용 Google 검색, 원문 인용 검증, 검증 시간 제한은 유지합니다.

N개 벡터, D차원, 결과 k개에 대해 시간은 O(ND + Nk)입니다. 상위 k개를 정렬된 작은 배열에 유지하고 k는 실제 앱에서 4입니다. C의 추가 메모리는 O(D + k)이며, Python 연결에서 저장 벡터를 연속된 float32 버퍼로 준비할 때 O(ND) 공간을 사용할 수 있습니다. C로 바꿨다는 이유만으로 전체 앱 알림 속도나 사실 검증 정확도가 높아졌다고 주장하지 않습니다.

## 빌드와 검사

C11 컴파일러(GCC 또는 Clang 계열)가 필요합니다. 다른 컴파일러는 `CC` 환경 변수로 지정합니다.

```sh
python backend/build_c_search.py
python tests/sequential_search_test.py
python tests/lightrag_retrieval_contract_test.py
cc -std=c11 -I backend backend/sequential_search.c tests/sequential_search_c_test.c -lm -o c-search-test
./c-search-test
```

`sequential_search.c`와 헤더는 Python 없이 일반 C 코드로도 컴파일할 수 있습니다. Python 연결·LightRAG 검사에는 서버의 Python 의존성과 원문 색인이 추가로 필요합니다. 전체 자료는 [백엔드 소스 ZIP](https://reelproof-mobile.vercel.app/downloads/reelproof-backend.zip)에 있습니다. 플랫폼별 공유 라이브러리는 ZIP에 넣지 않고 해당 실행 환경에서 빌드합니다. 키·인증서는 포함하지 않습니다.

프로덕션 `/health`의 `retrieval_strategy: sequential_cosine_scan`, `retrieval_implementation: c`로 C 연결 여부를 확인할 수 있습니다. C 라이브러리가 없거나 로드되지 않으면 서버 초기화가 실패하며, Python 검색으로 몰래 전환하지 않습니다. 이 상태 값은 검색 구현을 나타내며 모델 정확도를 보장하지 않습니다. 기존 앱 재설치는 필요하지 않습니다.
