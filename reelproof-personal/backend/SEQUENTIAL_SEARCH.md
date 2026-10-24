# ReelProof 순차탐색 위치

실행 코드: `backend/sequential_search.py`

- `sequential_top_k()`: `for index, vector in enumerate(vectors)`에서 원문 조각의 벡터를 처음부터 끝까지 하나씩 비교합니다. `np.dot(vector, query)`는 현재 조각 하나의 코사인 유사도를 계산합니다. 문서 전체 행렬을 한 번에 곱하지 않습니다.
- 임계값을 통과한 결과 중 유사도가 높은 최대 4개를 유지합니다. 처음 발견한 결과에서 멈추지 않습니다. 동점은 저장 순서를 따릅니다.
- `SequentialChunkQuery.__call__()`: LightRAG의 원문 벡터 저장소와 이 함수를 연결하고 ID·출처 메타데이터를 반환합니다.
- `install_sequential_search(rag)`: 해당 LightRAG 인스턴스의 원문 조각 검색만 교체합니다. 라이브러리 설치 파일을 수정하지 않습니다.

연결 위치: `backend/app.py`의 `initialize()`에서 `install_sequential_search(rag)`를 호출합니다. `verify_claim()`은 기존처럼 `rag.aquery_data(... QueryParam(mode='naive', chunk_top_k=4, ...))`로 원문을 요청하며, 이때 위의 순차탐색이 실행됩니다. 비활성 OpenAI 공급자 경로도 `backend/openai_backend.py`에서 같은 함수를 연결합니다.

전체 흐름은 **주장 → 임베딩 → 각 원문 벡터를 순차 비교 → 최대 4개 원문 → Gemini의 원문 대조 → 주장별 알림**입니다. 각 문서를 AI에게 하나씩 보내는 방식이 아닙니다. AI 판단 전의 검색 알고리즘만 변경했습니다. 최신 사건의 Google 검색 경로는 별도로 유지합니다.

조회 벡터와 저장된 벡터의 크기는 같아야 합니다. 코사인 유사도를 위해 조회 벡터를 정규화하며, 저장된 벡터는 NanoVectorDB가 이미 정규화한 것을 사용합니다. 데이터가 N개, 차원이 D, 선택 개수가 k라면 시간은 O(ND + N log k), 추가 공간은 O(D + k)입니다. 데이터가 늘면 탐색 시간도 증가하며, 검색 변경만으로 더 빠르거나 사실 검증 정확도가 높아진다고 주장하지 않습니다.

현재 프로덕션 서버의 `/health`에서 `retrieval_strategy: sequential_cosine_scan`으로 연결 여부를 확인할 수 있습니다. 이 값은 연결 방식을 나타내며 모델 판정 성공이나 정확도 보장은 아닙니다.

검사:

```sh
python tests/sequential_search_test.py
python tests/lightrag_retrieval_contract_test.py
```

전체 서버의 공개 원문 색인·모델 파일은 사이트의 [백엔드 소스 ZIP](https://reelproof-mobile.vercel.app/downloads/reelproof-backend.zip)에 포함됩니다. API 키는 포함하지 않습니다. GitHub 코드만 보고 알고리즘 위치를 확인하거나, 전체 ZIP을 받아 서버 구성을 재현할 수 있습니다. 기존 앱은 서버 주소를 그대로 사용하므로 앱 재설치가 필요하지 않습니다.
