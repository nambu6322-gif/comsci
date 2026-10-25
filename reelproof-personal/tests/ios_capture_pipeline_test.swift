import Foundation

@main struct CapturePipelineTests {
    static func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
    static func item(_ lane: VerificationWorkQueue.Lane, _ text: String) -> VerificationWorkQueue.Work {
        VerificationWorkQueue.Work(lane: lane, data: Data(text.utf8), preview: text)
    }
    static func main() throws {
        let model = try TextModel(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let claim = "금성은 태양계에서 가장 뜨거운 행성이다."
        let screen = "팔로우\n좋아요\n공유\n\(claim)\n댓글 123개\n원본 오디오"
        expect(model.score(claim) >= model.threshold && model.score(screen) < model.threshold, "Reproduce the real whole-frame suppression bug with the shipped weights")
        expect(model.selectedClaims(in: screen).contains(claim), "Score the claim independently of unrelated screen controls")
        expect(model.selectedClaims(in: claim + "\n" + claim).filter { $0 == claim }.count == 1, "Deduplicate OCR sentences")
        expect(model.selectedClaims(in: "좋아요\n공유\n팔로우").isEmpty, "Do not force control text through verification")
        expect((try? TextModel(data: Data("{}".utf8))) == nil, "Invalid resources throw rather than crashing the extension")
        let queue = VerificationWorkQueue(), audio = item(.audio, "audio-1"), a = item(.screen, "claim-a"), b = item(.screen, "claim-b"), c = item(.screen, "claim-c")
        expect(queue.offer(audio, now: 0) == .start, "Start audio lane")
        expect(queue.offer(a, now: 1) == .start, "Slow audio must not block OCR verification")
        expect(queue.offer(a, now: 2) == .duplicate, "Do not duplicate an active OCR request")
        expect(queue.offer(b, now: 3) == .queued && queue.offer(c, now: 4) == .queued, "Retain latest pending OCR")
        expect(queue.pending[.screen]?.id == c.id && queue.active.count == 2 && queue.pending.count == 1, "Bound concurrent work and supersede obsolete pending content")
        let next = queue.finish(a, success: true, now: 5)
        expect(next?.id == c.id && queue.active[.screen]?.id == c.id, "Dispatch newest pending claim after the current request")
        expect(queue.finish(a, success: true, now: 6) == nil && queue.active[.screen]?.id == c.id, "A stale callback cannot clear newer work")
        expect(queue.offer(a, now: 7) == .duplicate, "Avoid immediate successful result spam")
        _ = queue.finish(c, success: false, now: 8)
        expect(queue.offer(c, now: 9) == .duplicate && queue.offer(c, now: 19) == .start, "A failed claim can retry after a short cooldown, even when OCR text is unchanged")
        _ = queue.finish(c, success: true, now: 20);_ = queue.finish(audio, success: true, now: 21)
        expect(queue.offer(a, now: 100) == .start, "A later revisit may be checked again")
        queue.reset();expect(queue.active.isEmpty && queue.pending.isEmpty, "Stop/pause releases pending private content")
        expect(model.selectedClaims(in: "금성은 태양계에서 가장\n뜨거운 행성이다.").contains(claim), "Join wrapped article/video caption rows before selecting claims")
        var sourceStream = VerificationStream()
        if case .content? = try sourceStream.consume("{\"event\":\"content\",\"content\":{\"title\":\"뉴스 기사\"}}") {} else { fatalError("Read content metadata before results") }
        expect(!sourceStream.finished && sourceStream.resultCount == 0, "Extracted source is not a verdict")
        var stream = VerificationStream()
        let valid = "{\"event\":\"result\",\"result\":{\"status\":\"analyzed\",\"verdict\":\"SUPPORTS\",\"claims\":[{\"claim\":\"명시된 주장\"}]}}"
        if case .result? = try stream.consume(valid) {} else { fatalError("Deliver first complete claim before done") }
        expect(stream.resultCount == 1 && !stream.finished, "One result must not await a slow second claim")
        _ = try stream.consume("{\"event\":\"done\"}")
        expect(stream.finished, "Require explicit completion")
        do { _ = try stream.consume(valid); fatalError("Reject data after done") } catch {}
        var missing = VerificationStream()
        do { _ = try missing.consume("{\"event\":\"done\"}"); fatalError("No success without a result") } catch {}
        var failed = VerificationStream()
        _ = try failed.consume(valid)
        do { _ = try failed.consume("{\"event\":\"error\",\"status\":503}"); fatalError("A partial request failure is not full success") }
        catch let error as VerificationStream.Failure { expect(error.status == 503 && !failed.finished, "Keep earlier explicit claim result; do not fabricate the rest") }
        print("PASS real selector regression: claim score \(model.score(claim)), whole-screen score \(model.score(screen)); per-sentence selection, independent audio/OCR lanes, latest pending work, bounded concurrency, deduplication, retry and stale callback protection.")
    }
}
