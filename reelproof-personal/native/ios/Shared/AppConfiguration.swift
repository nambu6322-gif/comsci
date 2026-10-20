import Foundation

enum AppConfiguration {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "ReelProofAppGroup") as? String ?? "group.app.reelproof.shared"
    }
    static var broadcastExtension: String? {
        // Re-signing can change the extension's Bundle ID. Read the embedded
        // extension after signing instead of filtering by the original ID.
        guard let directory = Bundle.main.builtInPlugInsURL,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where entry.pathExtension == "appex" {
            guard let bundle = Bundle(url: entry),
                  let metadata = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
                  metadata["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload" else { continue }
            return bundle.bundleIdentifier
        }
        return nil
    }
}
