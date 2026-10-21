import Foundation
import CryptoKit

/// Serialized by SampleHandler's queue. Audio transcription cannot block OCR;
/// each lane retains one in-flight request plus the latest pending item only.
final class VerificationWorkQueue {
    enum Lane: String, CaseIterable { case screen, audio }
    struct Work {
        let id = UUID()
        let lane: Lane
        let data: Data
        let preview: String
        let fingerprint: String
        init(lane: Lane, data: Data, preview: String, identity: Data? = nil) {
            self.lane = lane; self.data = data; self.preview = preview
            fingerprint = lane.rawValue + ":" + SHA256.hash(data: identity ?? data).map { String(format: "%02x", $0) }.joined()
        }
    }
    enum Offer { case start, queued, duplicate }
    private(set) var active: [Lane: Work] = [:]
    private(set) var pending: [Lane: Work] = [:]
    private var completed: [String: TimeInterval] = [:]
    private var failed: [String: TimeInterval] = [:]
    func offer(_ work: Work, now: TimeInterval) -> Offer {
        if active[work.lane]?.fingerprint == work.fingerprint || pending[work.lane]?.fingerprint == work.fingerprint { return .duplicate }
        if let at = completed[work.fingerprint], now - at < 90 { return .duplicate }
        if let at = failed[work.fingerprint], now - at < 10 { return .duplicate }
        if active[work.lane] == nil { active[work.lane] = work; return .start }
        pending[work.lane] = work
        return .queued
    }
    func finish(_ work: Work, success: Bool, now: TimeInterval) -> Work? {
        guard active[work.lane]?.id == work.id else { return nil }
        active[work.lane] = nil
        if success { completed[work.fingerprint] = now; failed[work.fingerprint] = nil }
        else { failed[work.fingerprint] = now }
        if completed.count > 256, let oldest = completed.min(by: { $0.value < $1.value })?.key { completed[oldest] = nil }
        if failed.count > 256, let oldest = failed.min(by: { $0.value < $1.value })?.key { failed[oldest] = nil }
        guard let next = pending.removeValue(forKey: work.lane) else { return nil }
        active[work.lane] = next
        return next
    }
    func reset() { active = [:]; pending = [:]; completed = [:]; failed = [:] }
}
