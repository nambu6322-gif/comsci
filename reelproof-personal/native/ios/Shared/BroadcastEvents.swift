import Foundation
import CoreFoundation

/// Status-only signals. No credentials, claims, or audio travel through Darwin
/// notifications; the random session ID correlates this host with its extension.
enum BroadcastEvents {
    enum Event: String, CaseIterable {
        case connected, stopped, statusRequest
        case videoFrames, textRead, noText, modelFailed, audioCapturing, audioFailed, claimSelected, noClaim
        case screenSent, screenQueued, screenSkipped, screenDone, screenFailed
        case audioSent, audioQueued, audioSkipped, audioDone, audioRequestFailed
        case notificationSubmitted, notificationFailed
        var progress: (category: String, message: String)? {
            switch self {
            case .videoFrames: return ("화면 수신", "화면 프레임 수신됨")
            case .textRead: return ("자막 인식", "문자를 인식함")
            case .noText: return ("자막 인식", "읽을 수 있는 자막 없음")
            case .modelFailed: return ("주장 선별", "기기 내 선별 모델 읽기 실패")
            case .audioCapturing: return ("음성 수신", "앱 음성 조각 수집 중")
            case .audioFailed: return ("음성 수신", "앱 음성 조각 처리 실패")
            case .claimSelected: return ("주장 선별", "문장별 임계값을 통과한 주장 있음")
            case .noClaim: return ("주장 선별", "검증 대상으로 선별된 문장 없음")
            case .screenSent: return ("자막 검증", "검증 요청 중 · 아직 판정 아님")
            case .screenQueued: return ("자막 검증", "최신 자막 요청 대기 중")
            case .screenSkipped: return ("자막 검증", "서버에서 검증할 주장으로 선별되지 않음")
            case .screenDone: return ("자막 검증", "원문 검증 응답 수신")
            case .screenFailed: return ("자막 검증", "서버 검증 요청 실패")
            case .audioSent: return ("음성 검증", "음성 인식·검증 요청 중 · 아직 판정 아님")
            case .audioQueued: return ("음성 검증", "최신 음성 요청 대기 중")
            case .audioSkipped: return ("음성 검증", "인식한 음성 또는 검증할 주장 없음")
            case .audioDone: return ("음성 검증", "음성·원문 검증 응답 수신")
            case .audioRequestFailed: return ("음성 검증", "음성·서버 검증 요청 실패")
            case .notificationSubmitted: return ("알림", "알림센터에 요청 전달됨 · 배너 표시와 별도")
            case .notificationFailed: return ("알림", "알림 요청 실패")
            default: return nil
            }
        }
    }
    static func sessionID() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    static func name(session: String, event: Event) -> String? {
        guard session.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else { return nil }
        return "app.reelproof.broadcast.\(session).\(event.rawValue)"
    }
    static func post(session: String?, event: Event) {
        guard let session = session, let value = name(session: session, event: event) else { return }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue: value as CFString), nil, nil, true)
    }
    final class Observer {
        private var events: [String: Event] = [:]
        private var receive: ((Event) -> Void)?
        func listen(session: String, receive: @escaping (Event) -> Void) {
            stop()
            self.receive = receive
            for event in Event.allCases {
                guard let value = BroadcastEvents.name(session: session, event: event) else { continue }
                events[value] = event
                CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, name, _, _ in
                    guard let observer = observer, let name = name else { return }
                    let target = Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue()
                    let key = name.rawValue as String
                    DispatchQueue.main.async { [weak target] in
                        guard let target = target, let event = target.events[key] else { return }
                        target.receive?(event)
                    }
                }, value as CFString, nil, .deliverImmediately)
            }
        }
        func stop() {
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
            events = [:]; receive = nil
        }
        deinit { stop() }
    }
}
