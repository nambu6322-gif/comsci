// Completed claim results only; extraction metadata is never a truth verdict.
export async function readContentStream(response, onEvent) {
  if (!response.ok) {
    let value = {}; try { value = await response.json(); } catch {}
    throw new Error(typeof value.detail === 'string' ? value.detail : '내용 추출 서버 응답을 확인하지 못했습니다.');
  }
  if (!response.headers.get('content-type')?.includes('application/x-ndjson') || !response.body) throw new Error('내용 추출 응답 형식을 확인하지 못했습니다.');
  const reader = response.body.getReader(), decoder = new TextDecoder();
  let pending = '', finished = false, resultCount = 0, failureCount = 0, contentSeen = false;
  async function consume(line) {
    if (!line.trim()) return;
    if (finished || line.length > 192000) throw new Error('검증 응답 범위를 확인하지 못했습니다.');
    const value = JSON.parse(line);
    if (value.event === 'content') {
      if (contentSeen || resultCount + failureCount || !value.content || typeof value.content !== 'object') throw new Error('추출 내용 응답 오류');
      contentSeen = true;
    } else if (value.event === 'result') {
      if (++resultCount + failureCount > 3 || !value.result || !['analyzed', 'skipped'].includes(value.result.status)) throw new Error('검증 결과 응답 오류');
    } else if (value.event === 'claim_error') {
      if (++failureCount + resultCount > 3 || typeof value.claim !== 'string' || typeof value.message !== 'string') throw new Error('주장 오류 응답 형식 오류');
    } else if (value.event === 'done') {
      if (!resultCount && !failureCount) throw new Error('검증 결과 없이 응답이 종료됐습니다.');
      finished = true;
    } else if (value.event === 'error') throw new Error(typeof value.message === 'string' ? value.message : '내용 추출·검증을 완료하지 못했습니다.');
    else throw new Error('알 수 없는 검증 응답입니다.');
    await onEvent(value);
  }
  try {
    while (!finished) {
      const { value, done } = await reader.read();
      pending += decoder.decode(value, { stream: !done });
      if (pending.length > 384000) throw new Error('검증 응답 크기를 초과했습니다.');
      const lines = pending.split('\n'); pending = lines.pop();
      for (const line of lines) { await consume(line); if (finished) break; }
      if (done) { if (pending.trim()) await consume(pending); break; }
    }
    if (!finished) throw new Error('검증 연결이 중간에 끊겼습니다. 이미 표시된 결과는 해당 주장에 대한 판정입니다.');
    return { resultCount, failureCount };
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
}
