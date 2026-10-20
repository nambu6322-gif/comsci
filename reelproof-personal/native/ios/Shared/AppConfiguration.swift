import Foundation

enum AppConfiguration {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "ReelProofAppGroup") as? String ?? "group.app.reelproof.shared"
    }
    static var broadcastExtension: String {
        Bundle.main.object(forInfoDictionaryKey: "ReelProofBroadcastExtension") as? String ?? "app.reelproof.ios.BroadcastExtension"
    }
}
