import assert from 'node:assert/strict';
import { readContentStream } from '../web-mobile/content-stream.mjs';
function response(parts) { const encoder = new TextEncoder(); return new Response(new ReadableStream({ start(c) { for (const p of parts) c.enqueue(encoder.encode(p)); c.close(); } }), { headers: { 'Content-Type': 'application/x-ndjson' } }); }
const events = [];
const value = await readContentStream(response(['{"event":"content","content":{"title":"뉴스"}}\n{"event":"res', 'ult","result":{"status":"analyzed","claims":[]}}\n', '{"event":"done"}\n']), e => events.push(e));
assert.equal(value.resultCount, 1); assert.deepEqual(events.map(e => e.event), ['content','result','done']);
await assert.rejects(() => readContentStream(response(['{"event":"done"}\n']), () => {}));
const partial = [];
await assert.rejects(() => readContentStream(response(['{"event":"result","result":{"status":"analyzed"}}\n{"event":"error","message":"검색 한도"}\n']), e => partial.push(e)), /검색 한도/);
assert.equal(partial.length, 1);
await assert.rejects(() => readContentStream(response(['{"event":"result","result":{"status":"skipped"}}\n']), () => {}), /끊겼/);
console.log('PASS content stream: split network lines, extraction is not verdict, explicit completion, partial results retained on provider errors, premature close rejected.');

const failedOnly = await readContentStream(response(['{"event":"claim_error","claim":"대상 주장","message":"검색 한도"}\n{"event":"done"}\n']), () => {});
assert.equal(failedOnly.failureCount, 1); assert.equal(failedOnly.resultCount, 0);
