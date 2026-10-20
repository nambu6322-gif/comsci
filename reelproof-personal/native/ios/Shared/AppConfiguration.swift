import Foundation

enum AppConfiguration {
    static var configuredAppGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "ReelProofAppGroup") as? String ?? "group.app.reelproof.shared"
    }
    static var appGroup: String { sharing.group ?? configuredAppGroup }
    static var sharedDefaults: UserDefaults? {
        guard let group = sharing.group else { return nil }
        return UserDefaults(suiteName: group)
    }
    private static var hostBundle: Bundle {
        guard Bundle.main.bundleURL.pathExtension == "appex" else { return Bundle.main }
        return Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) ?? Bundle.main
    }
    private static var uploadBundle: Bundle? {
        guard let directory = hostBundle.builtInPlugInsURL,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        return entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).compactMap { url -> Bundle? in
            guard url.pathExtension == "appex", let bundle = Bundle(url: url),
                  let metadata = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
                  metadata["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload" else { return nil }
            return bundle
        }.first
    }
    static var broadcastExtension: String? { uploadBundle?.bundleIdentifier }
    private static func claims(_ bundle: Bundle?) -> [String]? {
        guard let url = bundle?.executableURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SigningGroups.signedGroups(data)
    }
    private static func profile(_ bundle: Bundle?) -> [String]? {
        guard let url = bundle?.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return SigningGroups.profileGroups(data)
    }
    static let sharing: SigningGroups.Resolution = {
        guard let upload = uploadBundle else {
            return SigningGroups.Resolution(group: nil, reason: "방송 확장이 없습니다. 확장을 제거하지 않고 앱과 함께 설치해야 합니다.")
        }
        return SigningGroups.resolve(configured: configuredAppGroup, appClaims: claims(hostBundle), extensionClaims: claims(upload), appProfile: profile(hostBundle), extensionProfile: profile(upload)) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()
    static var sharingDiagnostics: String {
        func display(_ groups: [String]?) -> String { groups.map { $0.isEmpty ? "없음" : $0.joined(separator: ", ") } ?? "읽지 못함" }
        return [sharing.reason,
                "구성 그룹: \(configuredAppGroup)",
                "앱 서명 그룹: \(display(claims(hostBundle)))",
                "방송 확장 서명 그룹: \(display(claims(uploadBundle)))",
                "앱 프로필 그룹: \(display(profile(hostBundle)))",
                "방송 확장 프로필 그룹: \(display(profile(uploadBundle)))",
                "사용할 그룹: \(sharing.group ?? "없음")"].joined(separator: "\n")
    }
}
