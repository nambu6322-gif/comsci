import { VoiceRecorder } from './recorder.mjs?v=14';
import { readContentStream } from './content-stream.mjs?v=14';
const el = id => document.getElementById(id);
const ios = /iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const standalone = () => navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;
const dialog = document.createElement('dialog');
dialog.id = 'webCheck';
dialog.innerHTML = `
<button class="web-close" id="webClose" aria-label="닫기">×</button>
<span class="tag">IPHONE · IPAD · WEB APP</span><h2 class="sheet-title">듣고, 읽고,<br>AI로 살펴보기.</h2>
<p class="description">유튜브·뉴스 기사 링크에서 주장을 찾거나, 직접 녹음하고 텍스트로 확인하세요.</p>
<details class="permission-guide"><summary>마이크·알림 권한과 사용 범위</summary>
<div class="permission-row"><span>마이크 <small id="micPermission">녹음 시작 시 요청</small></span><b>직접 녹음</b></div>
<div class="permission-row"><span>화면·다른 앱 소리 <small>iPhone 웹앱에서 자동 추출 불가</small></span><b>지원 안 됨</b></div>
<div class="permission-row"><span>완료 알림 <small id="notificationStatus">지원 여부 확인 중</small></span><button type="button" id="enableNotifications" class="web-link">알림 설정</button></div>
<p class="small-note">마이크는 주변 음성을 녹음하며 다른 앱의 재생 소리를 직접 읽지 않습니다. 웹앱을 벗어나면 녹음을 중지합니다. 알림을 허용해도 릴스를 자동 감시하지 않으며, 백그라운드 분석·푸시는 제공하지 않습니다.</p></details>
<div class="web-status" id="webStatus" role="status">서버 상태 확인 중…</div><button id="refreshEngine" class="web-link">서버 상태 다시 확인</button>
<form id="webForm"><label for="webMode">확인할 내용</label><select id="webMode"><option value="record">마이크로 직접 녹음</option><option value="url">유튜브·뉴스 기사 링크</option><option value="text">주장 텍스트 붙여 넣기</option><option value="audio">저장한 음성 파일</option></select>
<div id="webRecordGroup" class="record-box"><p id="recordStatus" role="status">최대 45초 · 녹음 후 직접 전송</p><div class="record-actions"><button type="button" id="recordStart" class="sheet-button">마이크 허용하고 녹음</button><button type="button" id="recordStop" class="sheet-button secondary" hidden>■ 녹음 중지</button></div><audio id="recordPreview" controls hidden></audio><button type="button" id="recordDelete" class="web-link" hidden>녹음 지우기</button><p class="small-note">주장을 읽어 주거나 다른 기기에서 재생한 음성을 녹음하세요. 녹음은 근거 확인 버튼을 누르기 전까지 서버로 전송되지 않습니다.</p></div>
<div id="webUrlGroup" hidden><label for="webUrl">유튜브 영상·뉴스 기사 HTTPS 링크</label><input id="webUrl" type="url" maxlength="2048" autocomplete="off" autocapitalize="none" spellcheck="false" placeholder="https://www.youtube.com/watch?v=…"><label for="webVideoStart">유튜브 시작 위치 · 초 (선택)</label><input id="webVideoStart" type="number" min="0" max="43200" step="1" placeholder="비우면 링크의 시작 시각 사용"><p class="small-note">영상은 선택 위치부터 60초 구간, 기사는 추출 본문에서 최대 3개 사실 주장을 골라 확인합니다. 로그인·유료·차단 콘텐츠는 읽지 못할 수 있습니다. 입력 자료 자체는 검증 근거에서 제외합니다.</p></div>
<div id="webTextGroup" hidden><label for="webText">영상 속 주장</label><textarea id="webText" rows="4" maxlength="12000" placeholder="영상에서 들은 사실 주장을 문장으로 입력하세요."></textarea><label><input id="webSearch" type="checkbox"> 웹 검색으로 최신·지역 사건 확인</label><p class="small-note">사망설·화재 등 사건 표현은 자동으로 웹 검색합니다. 검색 원문을 읽을 수 없으면 판별 불가로 표시합니다. Google 검색이 제한되면 공개 뉴스 RSS에서 찾은 원문을 대조합니다.</p></div>
<div id="webAudioGroup" hidden><label for="webAudio">저장한 음성 · WAV / M4A / MP3</label><input id="webAudio" type="file" accept=".wav,.m4a,.mp3,audio/wav,audio/mp4,audio/mpeg"><p class="small-note">2.5MB 이하. 전송하면 AI 서버가 음성을 전사하고 주장을 검증합니다.</p></div>
<label for="webKey">검증 서버 접근 키</label><input id="webKey" type="password" autocomplete="off" autocapitalize="none" spellcheck="false" placeholder="AI API 키가 아닌 앱 전용 접근 키"><p class="small-note">접근 키는 화면을 닫으면 지워집니다. 전송한 내용은 검증 서버와 Gemini에서 처리됩니다.</p>
<button id="webSubmit" class="sheet-button" type="submit" disabled>서버 상태 확인 중</button><button id="webCancel" class="web-link" type="button" hidden>요청 중단</button></form>
<section id="webResult" class="web-result" aria-live="polite" hidden></section>
<p id="verificationNote" class="small-note">FEVER·WHO·NASA 원문 122개를 검색하고 사건별 웹 원문 검색을 요청합니다. API 요청은 서버 작업자별 최소 4초 간격이며, 검색 공급자 제한 시 공개 뉴스 RSS 경로를 사용합니다. 모든 사건·한국어 릴스에 대한 검증 정확도가 평가된 서비스는 아닙니다. 근거 부족은 거짓이라는 뜻이 아니며 영상의 AI 제작 여부는 판별하지 않습니다.</p>`;
document.body.append(dialog);
let verificationMode = 'evidence';
let ready = false, busy = false, recording = null, previewUrl = null, requestController = null, healthVersion = 0;
let registration = null;
const swReady = 'serviceWorker' in navigator
  ? navigator.serviceWorker.register('/sw.js').then(() => navigator.serviceWorker.ready).then(r => { registration = r; notificationsUI(); return r; }).catch(() => null)
  : Promise.resolve(null);

function buttons() {
  el('webSubmit').disabled = !ready || busy || recorder.state !== 'idle';
  el('webSubmit').textContent = busy ? 'AI 판단을 요청하고 있어요…' : ready ? verificationMode === 'knowledge_only' ? 'Gemini 자체지식 판단 요청' : '근거 확인 · 서버로 전송' : '서버 활성화 대기';
  el('webCancel').hidden = !busy;
  el('webMode').disabled = busy || recorder.state !== 'idle';
  el('recordStart').disabled = busy || recorder.state !== 'idle' || !recorder.supported();
  el('recordStop').hidden = recorder.state !== 'recording';
  el('recordStart').hidden = recorder.state === 'recording';
}
function judgmentLabel(value) {
  const assessment = value.knowledge_assessment?.assessment;
  if (assessment) return { LIKELY_TRUE: 'AI 추정 · 사실일 가능성이 높음', LIKELY_FALSE: 'AI 추정 · 오류일 가능성이 높음', UNCERTAIN: 'AI 추정 · 판단 불확실' }[assessment] || 'AI 추정 · 판단 불확실';
  return { SUPPORTS: '원문 근거가 뒷받침함', REFUTES: '원문 근거와 충돌함', NOT_ENOUGH_INFO: '근거 부족 · 판별 불가' }[value.verdict] || '판별 불가';
}
function message(title, text) {
  const result = el('webResult'); result.replaceChildren(); result.hidden = false;
  const h = document.createElement('h3'); h.textContent = title;
  const p = document.createElement('p'); p.textContent = text; result.append(h, p);
}
async function renderContent(response) {
  let results = 0, failures = 0;
  await readContentStream(response, async event => {
    if (event.event === 'content') {
      const value = event.content;
      if (value.verification_mode) verificationMode = value.verification_mode;
      message(value.title || '추출한 내용', value.scope || '선별한 주장 확인');
      el('webResult').dataset.contentStream = '1';
      try { const u = new URL(value.url); if (u.protocol === 'https:') { const a = document.createElement('a'); a.href = u.href; a.rel = 'noopener noreferrer'; a.target = '_blank'; a.textContent = '입력 자료 보기 ↗'; el('webResult').append(a); } } catch {}
      const excerpt = document.createElement('p'); excerpt.textContent = value.excerpt || ''; el('webResult').append(excerpt);
      const list = document.createElement('ol');
      for (const item of value.claims || []) { const li = document.createElement('li'); li.textContent = item.claim; list.append(li); }
      el('webResult').append(list);
      const note = document.createElement('p'); note.textContent = verificationMode === 'knowledge_only' ? 'Gemini 자체지식 추정 모드입니다. 외부 검색이나 원문 근거 대조는 수행하지 않습니다.' : '추출한 주장을 다른 원문과 대조 중입니다. 위의 입력 자료는 검증 근거가 아닙니다.'; el('webResult').append(note);
    } else if (event.event === 'result') {
      const data = event.result;
      if (data.status === 'skipped') { const p = document.createElement('p'); p.textContent = data.message || '검증할 주장이 없습니다.'; el('webResult').append(p); return; }
      for (const claim of data.claims || []) {
        results++;
        const section = document.createElement('section'), h = document.createElement('h3'), text = document.createElement('p'), reason = document.createElement('p');
        h.textContent = judgmentLabel(claim);
        text.textContent = claim.claim; reason.textContent = claim.reason; section.append(h, text, reason);
        for (const evidence of claim.evidence || []) {
          const quote = document.createElement('blockquote'); quote.textContent = evidence.quote; section.append(quote);
          try { const u = new URL(evidence.source); if (u.protocol === 'https:') { const a = document.createElement('a'); a.href = u.href; a.rel = 'noopener noreferrer'; a.target = '_blank'; a.textContent = '검증 근거 원문 ↗'; section.append(a); } } catch {}
        }
        if (claim.search) { const p = document.createElement('p'); p.textContent = (claim.search.provider === 'bing_news_rss' ? '공개 뉴스 RSS 검색' : 'Google 검색') + ' · 확인일 ' + claim.search.checked_at + ' · 직접 읽은 원문 ' + claim.search.readable_originals + '개'; section.append(p); }
        el('webResult').append(section);
      }
    } else if (event.event === 'claim_error') {
      failures++; const section = document.createElement('section'), h = document.createElement('h3'), p = document.createElement('p'); h.textContent = '검증 미완료 · 진위 판정 아님'; p.textContent = event.claim + '\n' + event.message; section.append(h, p); el('webResult').append(section);
    } else if (event.event === 'done') {
      const p = document.createElement('p'); p.textContent = results || failures ? '확인 결과 ' + results + '개 · 미완료 ' + failures + '개 · 영상·기사 전체의 진위 판정은 아닙니다.' : '검증할 사실 주장을 찾지 못했습니다.'; el('webResult').append(p);
    }
  });
  return { results, failures };
}
function clearRecording() {
  recording = null; el('recordPreview').pause(); el('recordPreview').removeAttribute('src'); el('recordPreview').load();
  if (previewUrl) URL.revokeObjectURL(previewUrl); previewUrl = null;
  el('recordPreview').hidden = true; el('recordDelete').hidden = true;
}
const recorder = new VoiceRecorder({
  onState(state) {
    buttons();
    if (state === 'requesting') el('recordStatus').textContent = '마이크 권한을 기다리고 있어요…';
    if (state === 'processing') el('recordStatus').textContent = '녹음 파일을 준비하고 있어요…';
  },
  onTime(seconds) { el('recordStatus').textContent = '● 녹음 중 ' + seconds + ' / 45초'; },
  onAudio(blob) {
    clearRecording(); recording = blob; previewUrl = URL.createObjectURL(blob);
    el('recordPreview').src = previewUrl; el('recordPreview').hidden = false; el('recordDelete').hidden = false;
    el('recordStatus').textContent = '녹음 준비됨 · ' + Math.ceil(blob.size / 1000) + 'KB · 아직 전송하지 않았어요';
    el('micPermission').textContent = '권한 허용 · 현재 녹음 종료';
  },
  onError(error) { el('recordStatus').textContent = error.message; }
});
el('recordStart').onclick = async () => {
  clearRecording();
  try { await recorder.start(); if (recorder.state === 'recording') el('micPermission').textContent = '권한 허용 · 녹음 중'; }
  catch (error) {
    const denied = ['NotAllowedError', 'PermissionDeniedError'].includes(error.name);
    el('recordStatus').textContent = denied ? '마이크 권한이 거부됐습니다. Safari의 웹사이트 설정에서 마이크를 허용한 뒤 다시 시도하세요.' : error.name === 'NotFoundError' ? '사용할 수 있는 마이크가 없습니다. 텍스트나 음성 파일을 선택하세요.' : error.message;
    el('micPermission').textContent = denied ? '권한 거부됨' : '사용할 수 없음';
  }
};
el('recordStop').onclick = () => recorder.stop();
el('recordDelete').onclick = () => { clearRecording(); el('recordStatus').textContent = '녹음을 지웠어요. 다시 녹음할 수 있습니다.'; };
if (!recorder.supported()) { el('recordStatus').textContent = '이 브라우저에서는 직접 녹음을 지원하지 않습니다. 텍스트나 음성 파일을 선택하세요.'; el('micPermission').textContent = '이 환경에서 지원 안 됨'; }

async function health() {
  const version = ++healthVersion;
  ready = false; buttons(); el('webStatus').textContent = '서버 상태 확인 중…';
  try {
    const response = await fetch('/api/engine/health', { cache: 'no-store', signal: AbortSignal.timeout(10000) });
    const data = await response.json(); if (version !== healthVersion) return;
    ready = response.ok && data.ready === true;
    verificationMode = data.verification_mode || 'evidence';
    el('webSearch').disabled = verificationMode === 'knowledge_only';
    if (verificationMode === 'knowledge_only') {
      el('webSearch').checked = false;
      el('verificationNote').textContent = 'Gemini 자체지식으로만 추정합니다. Google 검색·LightRAG 조회·외부 원문 검증은 꺼져 있습니다. AI API 요청은 서버 작업자별 최소 4초 간격입니다. 최근 사건이나 알려지지 않은 사실은 불확실할 수 있습니다.';
    }
    if (ready && verificationMode === 'knowledge_only') el('webStatus').textContent = 'Gemini 자체지식 추정 모드 · 외부 검색·원문 근거 대조 안 함 · AI API 요청 최소 4초 간격';
    else if (ready) el('webStatus').textContent = '서버 연결됨 · 등록 원문 ' + data.corpus_documents + '개 · 실제 판정은 요청 시 확인합니다.' + (data.web_search_status === 'public_rss_ready' ? ' 공개 뉴스 원문 검색 사용 중.' : data.web_search_status === 'rate_limited' ? ' 검색 공급자 제한 중 · 등록 원문 검증은 유지합니다.' : '');
    else if (data.generation_status === 'quota_exceeded') {
      const retry = Number(data.retry_after_seconds);
      el('webStatus').textContent = 'AI API 사용 한도 초과 · 현재 사실 검증 중단.' + (Number.isFinite(retry) && retry > 0 ? ' 재시도 가능 예상: ' + new Date(Date.now() + retry * 1000).toLocaleString('ko-KR') + '. 이후 상태를 다시 확인하세요.' : ' 한도 초기화 후 다시 확인하세요.');
    } else el('webStatus').textContent = '검증 불가 · ' + (data.reason || '서버가 준비되지 않았습니다. 잠시 후 상태를 다시 확인하세요.');
  } catch { if (version !== healthVersion) return; ready = false; el('webStatus').textContent = navigator.onLine ? '검증 서버에 연결하지 못했습니다.' : '오프라인입니다. 녹음은 가능하며 근거 확인에는 인터넷 연결이 필요합니다.'; }
  buttons();
}
function open() { if (!dialog.open) dialog.showModal(); notificationsUI(); health(); }
function cleanup() {
  el('webKey').value = ''; requestController?.abort(); ++healthVersion;
  recorder.cancel(); clearRecording(); el('webAudio').value = ''; el('recordStatus').textContent = '최대 45초 · 녹음 후 직접 전송';
}
el('webClose').onclick = () => { cleanup(); dialog.close(); }; dialog.addEventListener('close', cleanup); dialog.addEventListener('cancel', cleanup);
el('openWebCheck').onclick = open;
el('openContentCheck')?.addEventListener('click', () => { el('webMode').value = 'url'; el('webMode').dispatchEvent(new Event('change')); open(); }); window.addEventListener('reelproof-web-check', open); el('refreshEngine').onclick = health;
el('webMode').onchange = () => {
  const mode = el('webMode').value;
  for (const [id, value] of [['webUrlGroup', 'url'], ['webTextGroup', 'text'], ['webAudioGroup', 'audio'], ['webRecordGroup', 'record']]) el(id).hidden = mode !== value;
};
document.addEventListener('visibilitychange', () => {
  if (document.hidden && ['requesting', 'recording'].includes(recorder.state)) {
    recorder.cancel(); el('recordStatus').textContent = '다른 화면으로 이동해 녹음을 중단했어요. 이 화면에서 다시 녹음하세요.';
    el('micPermission').textContent = '현재 녹음 중지';
  }
});
window.addEventListener('pagehide', cleanup);

function notificationsUI() {
  const button = el('enableNotifications'), status = el('notificationStatus');
  const supported = isSecureContext && 'Notification' in window && 'serviceWorker' in navigator;
  if (ios && !standalone()) { status.textContent = '홈 화면에 추가한 웹앱에서 설정'; button.textContent = '설치 안내'; button.disabled = false; return; }
  if (!supported) { status.textContent = '이 브라우저에서 지원 안 됨'; button.disabled = true; return; }
  status.textContent = Notification.permission === 'granted' ? '허용됨 · 이 화면에서 완료 시 표시' : Notification.permission === 'denied' ? '거부됨 · 기기 설정에서 변경' : '선택 사항 · 완료 시 표시';
  button.textContent = Notification.permission === 'granted' ? '알림 시험' : '알림 허용'; button.disabled = Notification.permission === 'denied' || !registration;
}
async function notify(title, test = false) {
  if (!registration || !('Notification' in window) || Notification.permission !== 'granted') return;
  try {
    await registration.showNotification(test ? 'ReelProof 알림 시험' : 'ReelProof · 확인 완료', {
      body: test ? '알림 표시 기능을 확인했습니다. 릴스 자동 감시는 지원하지 않습니다.' : title + ' · 앱에서 근거를 확인하세요.',
      icon: '/icon-192.png', tag: 'reelproof-check', data: { url: '/?check=1' }
    });
  } catch { el('notificationStatus').textContent = '시스템 알림을 표시하지 못했어요. 이 화면에서 결과를 확인하세요.'; }
}
el('enableNotifications').onclick = async () => {
  if (ios && !standalone()) { dialog.close(); install.showModal(); return; }
  try {
    // Invoke directly from the tap; do not await unrelated work before this call.
    const permission = await Notification.requestPermission(); notificationsUI();
    if (permission === 'granted') await notify('', true);
  } catch { el('notificationStatus').textContent = '알림 권한을 요청하지 못했습니다. 홈 화면의 웹앱에서 다시 확인하세요.'; }
};
notificationsUI();
el('webCancel').onclick = () => requestController?.abort();
el('webForm').onsubmit = async event => {
  event.preventDefault(); if (busy || recorder.state !== 'idle') return;
  if (!ready) { message('아직 검증할 수 없습니다.', '서버 상태를 확인한 뒤 다시 시도하세요.'); return; }
  const key = el('webKey').value.trim(); if (!key) { message('서버 접근 키가 필요합니다.', '관리자가 발급한 앱 전용 접근 키가 필요합니다. AI API 키를 입력하지 마세요.'); return; }
  const mode = el('webMode').value; let body, contentType, path;
  if (mode === 'url') {
    const url = el('webUrl').value.trim(), start = el('webVideoStart').value.trim();
    try { if (new URL(url).protocol !== 'https:') throw new Error(); } catch { message('링크를 확인하세요.', '공개 HTTPS 영상·기사 링크를 입력하세요.'); return; }
    const payload = { url, duration_seconds: 60 };
    if (start) { const value = Number(start); if (!Number.isInteger(value) || value < 0 || value > 43200) { message('시작 위치를 확인하세요.', '0~43200 사이의 초 단위 숫자가 필요합니다.'); return; } payload.start_seconds = value; }
    body = JSON.stringify(payload); contentType = 'application/json'; path = 'content/stream';
  } else if (mode === 'record') {
    if (!recording) { message('먼저 녹음하세요.', '녹음 시작을 누르고 마이크 권한을 허용한 뒤 녹음을 중지하세요.'); return; }
    body = recording; contentType = recording.type; path = 'audio?source=safari-web';
  } else if (mode === 'audio') {
    const file = el('webAudio').files[0];
    if (!file || file.size > 2500000 || !file.size) { message('음성 파일을 확인하세요.', '2.5MB 이하의 WAV, M4A 또는 MP3 파일이 필요합니다.'); return; }
    contentType = { wav: 'audio/wav', m4a: 'audio/mp4', mp3: 'audio/mpeg' }[file.name.split('.').pop().toLowerCase()];
    if (!contentType) { message('지원하지 않는 파일입니다.', 'WAV, M4A 또는 MP3 파일을 선택하세요.'); return; }
    body = file; path = 'audio?source=safari-web';
  } else {
    const text = el('webText').value.trim(); if (text.length < 5) { message('주장을 입력하세요.', '영상 속 사실 주장을 다섯 글자 이상 입력하세요.'); return; }
    body = JSON.stringify({ text, source: 'safari-web' }); contentType = 'application/json'; path = el('webSearch').checked ? 'analyze/web' : 'analyze';
  }
  busy = true; requestController = new AbortController(); const controller = requestController;
  const timeout = setTimeout(() => controller.abort('timeout'), mode === 'url' ? 210000 : 140000);
  delete el('webResult').dataset.contentStream;
  buttons(); message(mode === 'url' ? '영상·기사에서 주장 추출 중' : verificationMode === 'knowledge_only' ? 'Gemini 자체지식으로 판단 중' : '원문 근거 확인 중', '이 화면을 열어 두세요. 응답에는 수 초에서 수십 초가 걸릴 수 있습니다.');
  try {
    const response = await fetch('/api/engine/' + path, { method: 'POST', headers: { 'Content-Type': contentType, Authorization: 'Bearer ' + key }, body, signal: controller.signal });
    if (mode === 'url') { const count = await renderContent(response); await notify('확인 결과 ' + count.results + '개 · 미완료 ' + count.failures + '개'); return; }
    const data = await response.json();
    if (!response.ok) throw new Error(response.status === 401 ? '앱 전용 접근 키를 확인하세요.' : typeof data.detail === 'string' ? data.detail : '검증 서버 응답을 확인하지 못했습니다.');
    if (controller.signal.aborted || !dialog.open) return;
    const title = data.status === 'skipped' ? '검증할 주장으로 선별되지 않았습니다.' : data.verification_mode === 'knowledge_only' ? data.knowledge_assessment ? judgmentLabel(data) : 'Gemini 자체지식 추정' : { SUPPORTS: '원문 근거 있음', REFUTES: '원문 근거와 충돌', NOT_ENOUGH_INFO: '근거 부족 · 판별 불가' }[data.verdict] || '판별 불가';
    message(title, data.message || '확인할 근거가 부족합니다.');
    if (data.verification_mode === 'knowledge_only' && (data.claims || []).length > 1) for (const claim of data.claims) {
      const section = document.createElement('section'), h = document.createElement('h3'), p = document.createElement('p'), reason = document.createElement('p');
      h.textContent = judgmentLabel(claim); p.textContent = claim.claim; reason.textContent = claim.reason; section.append(h, p, reason); el('webResult').append(section);
    }
    for (const claim of data.claims || []) for (const evidence of claim.evidence || []) {
      const quote = document.createElement('blockquote'); quote.textContent = evidence.quote; el('webResult').append(quote);
      try { const u = new URL(evidence.source); if (u.protocol === 'https:') { const a = document.createElement('a'); a.href = u.href; a.target = '_blank'; a.rel = 'noopener noreferrer'; a.textContent = '원문 보기 ↗'; el('webResult').append(a); } } catch {}
    }
    for (const claim of data.claims || []) if (claim.search) {
      const p = document.createElement('p'); p.textContent = (claim.search.provider === 'bing_news_rss' ? '공개 뉴스 RSS 검색' : 'Google 검색') + ' · 확인일 ' + claim.search.checked_at + ' · 직접 읽은 원문 ' + claim.search.readable_originals + '개'; el('webResult').append(p);
      if (typeof claim.search.search_entry_point_html === 'string') {
        const frame = document.createElement('iframe'); frame.title = 'Google 검색 제안'; frame.setAttribute('sandbox', 'allow-popups allow-popups-to-escape-sandbox'); frame.referrerPolicy = 'no-referrer'; frame.srcdoc = claim.search.search_entry_point_html; frame.style.width = '100%'; frame.style.border = '0'; el('webResult').append(frame);
      }
    }
    if (data.transcript) { const p = document.createElement('p'); p.textContent = '인식한 음성: ' + data.transcript; el('webResult').append(p); }
    await notify(title);
  } catch (error) {
    if (!dialog.open) return;
    const aborted = controller.signal.aborted;
    const title = aborted ? '판별 불가 · 요청 중단' : '판별 불가 · 요청 실패';
    const detail = aborted ? controller.signal.reason === 'timeout' ? '응답 시간이 초과됐습니다. 잠시 후 다시 확인하세요.' : '요청을 중단했습니다. 이미 전송된 내용의 서버 처리는 계속될 수 있습니다.' : error.message;
    if (mode === 'url' && el('webResult').dataset.contentStream) { const h = document.createElement('h3'), p = document.createElement('p'); h.textContent = title; p.textContent = detail + ' 이미 표시된 결과는 해당 주장에 대한 판정입니다.'; el('webResult').append(h, p); } else message(title, detail);
  } finally { clearTimeout(timeout); if (requestController === controller) requestController = null; busy = false; buttons(); }
};
const install = document.createElement('dialog'); install.id = 'webInstall';
install.innerHTML = `<button class="web-close" id="installClose" aria-label="닫기">×</button><span class="tag">ADD TO HOME SCREEN</span><h2 class="sheet-title">iPhone·iPad에서 시작.</h2><section class="web-result"><h3>개인 테스트용 iPhone 앱</h3><p>앱과 방송 확장 빌드를 완료했습니다. Windows에서 본인 Apple 계정으로 서명한 뒤 설치하세요. 실기기 검증 전 연구 빌드입니다.</p><a class="sheet-button" href="/downloads/reelproof-ios-personal.ipa" download>개인 테스트용 IPA 내려받기 ↓</a><a class="web-link" href="/ios-personal.html">Windows에서 서명·설치하는 방법 ↗</a></section><h3>홈 화면 설치형 웹앱</h3><ol class="install-steps"><li>이 사이트를 <strong>Safari</strong>에서 여세요.</li><li>공유 버튼에서 <strong>홈 화면에 추가</strong>를 선택하세요. 메뉴에 없으면 더 보기에서 찾으세요.</li><li>추가된 <strong>ReelProof</strong> 아이콘으로 실행하세요.</li><li><strong>녹음·주장 확인 → 마이크 허용하고 녹음</strong>을 누르세요.</li><li>완료 알림은 웹앱의 <strong>알림 허용</strong>에서 선택할 수 있습니다. iOS·iPadOS 16.4 이상과 지원 브라우저가 필요합니다.</li></ol><p class="small-note">웹앱 설치에는 Apple Developer 가입이나 App Store Connect가 필요하지 않습니다. 다른 앱을 보는 동안의 자동 감시는 지원하지 않습니다. 알림은 이 검증 화면에서 완료된 요청에 한해 표시합니다.</p><button class="sheet-button" id="installToCheck">웹앱에서 녹음·주장 확인</button><a class="sheet-button secondary" href="/downloads/reelproof-ios-source.zip" download>iPhone·iPad 네이티브 소스 내려받기</a>`;
document.body.append(install); el('installClose').onclick = () => install.close(); el('installWeb').onclick = () => install.showModal();
el('installToCheck').onclick = () => { install.close(); open(); };
window.addEventListener('reelproof-ios-guide', () => install.showModal());
navigator.serviceWorker?.addEventListener('message', event => { if (event.data?.type === 'reelproof-open-check') open(); });
const wantsContent = new URLSearchParams(location.search).get('content') === '1';
const connectionToken = new URLSearchParams(location.hash.slice(1)).get('access_token');
if (wantsContent) { el('webMode').value = 'url'; el('webMode').dispatchEvent(new Event('change')); }
if (connectionToken) { history.replaceState(null, '', location.pathname + location.search); el('webKey').value = connectionToken; open(); }
else if (wantsContent || new URLSearchParams(location.search).get('check') === '1') open();
buttons();
