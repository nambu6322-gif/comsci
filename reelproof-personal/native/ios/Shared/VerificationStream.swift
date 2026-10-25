import Foundation

/// Only complete, source-checked claim verdicts are emitted by the server.
/// Partial JSON/model output is never interpreted as a truth judgment.
struct VerificationStream {
    static func assessmentLabel(_ value: String) -> String {
        switch value {
        case "LIKELY_TRUE": return "AI 추정 · 사실일 가능성이 높음"
        case "LIKELY_FALSE": return "AI 추정 · 오류일 가능성이 높음"
        default: return "AI 추정 · 판단 불확실"
        }
    }
    enum Event { case content([String: Any]), claimError([String: Any]), result([String: Any]), done }
    struct Failure: Error { let status: Int; let message: String }
    private var contentReceived = false
    private(set) var finished = false
    private(set) var resultCount = 0
    private(set) var failureCount = 0
    mutating func consume(_ line: String) throws -> Event? {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard !finished, line.utf8.count <= 192_000,
              let data = line.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = value["event"] as? String else { throw Failure(status: 502, message: "검증 응답 형식 오류") }
        switch event {
        case "content":
            guard !contentReceived, resultCount + failureCount == 0, let content = value["content"] as? [String: Any] else { throw Failure(status: 502, message: "콘텐츠 정보 형식 오류") }
            contentReceived = true; return .content(content)
        case "result":
            guard let result = value["result"] as? [String: Any], resultCount + failureCount < 3 else { throw Failure(status: 502, message: "검증 결과 형식 오류") }
            resultCount += 1; return .result(result)
        case "claim_error":
            guard resultCount + failureCount < 3, value["claim"] is String, value["message"] is String else { throw Failure(status: 502, message: "주장 오류 응답 형식 오류") }
            failureCount += 1; return .claimError(value)
        case "done":
            guard resultCount + failureCount > 0 else { throw Failure(status: 502, message: "검증 결과 없이 응답이 종료됐습니다.") }
            finished = true; return .done
        case "error": throw Failure(status: value["status"] as? Int ?? 503, message: value["message"] as? String ?? "검증 서버 응답 오류")
        default: throw Failure(status: 502, message: "알 수 없는 검증 응답")
        }
    }
}
