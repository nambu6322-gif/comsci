import Foundation

@main struct BroadcastEventsTests {
    static func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
    static func pump(until test: () -> Bool, seconds: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while !test(), Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    }
    static func child(_ session: String, _ event: BroadcastEvents.Event) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--post", session, event.rawValue];try process.run();process.waitUntilExit()
        expect(process.terminationStatus == 0, "Child status sender failed")
    }
    static func main() throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--post" {
            BroadcastEvents.post(session: CommandLine.arguments[2], event: BroadcastEvents.Event(rawValue: CommandLine.arguments[3])!);return
        }
        let session = BroadcastEvents.sessionID(), other = BroadcastEvents.sessionID()
        expect(BroadcastEvents.name(session: "invalid", event: .connected) == nil, "Reject uncorrelated event names")
        var seen: [BroadcastEvents.Event] = [];let observer = BroadcastEvents.Observer()
        observer.listen(session: session) { seen.append($0) }
        try child(other, .connected);pump(until: { !seen.isEmpty }, seconds: 0.2)
        expect(seen.isEmpty, "Another session cannot activate this host UI")
        try child(session, .connected);pump(until: { seen == [.connected] })
        expect(seen == [.connected], "Receive actual cross-process start status without shared rights")
        try child(session, .stopped);pump(until: { seen.count == 2 })
        expect(seen == [.connected,.stopped], "Receive stop status")
        observer.listen(session: other) { seen.append($0) }
        try child(session, .connected);pump(until: { seen.count > 2 }, seconds: 0.2)
        expect(seen.count == 2, "Ignore stale status after a new preparation")
        try child(other, .statusRequest);pump(until: { seen.count == 3 })
        expect(seen.last == .statusRequest, "Foreground refresh uses the current session")
        observer.stop();try child(other, .connected);pump(until: { seen.count > 3 }, seconds: 0.2)
        expect(seen.count == 3, "Stopped observer ignores late events")
        print("PASS actual Darwin IPC: separate process start/stop, session isolation, stale-event rejection, foreground request, cleanup; no App Group or Keychain rights.")
    }
}
