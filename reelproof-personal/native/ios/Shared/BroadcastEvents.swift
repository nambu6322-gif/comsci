import Foundation
import CoreFoundation

/// Status-only signals. No credentials, claims, or audio travel through Darwin
/// notifications; the random session ID correlates this host with its extension.
enum BroadcastEvents {
    enum Event: String, CaseIterable { case connected, stopped, statusRequest }
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
