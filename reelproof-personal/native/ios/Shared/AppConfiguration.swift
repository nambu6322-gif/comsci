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
    static var hostBundle: Bundle {
        guard Bundle.main.bundleURL.pathExtension == "appex" else { return Bundle.main }
        return Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) ?? Bundle.main
    }
    static var uploadBundle: Bundle? {
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

    static var sharedKeychainGroup: String? {
        func groups(_ bundle: Bundle?) -> Set<String> {
            guard let url = bundle?.executableURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let entitlements = SigningGroups.signedEntitlements(data),
                  let values = entitlements["keychain-access-groups"] as? [String] else { return [] }
            return Set(values.filter { !$0.contains("*") && !$0.contains("$(") })
        }
        return groups(hostBundle).intersection(groups(uploadBundle)).sorted().first
    }
    static func saveConnection(endpoint: String, token: String) throws -> String {
        // A common, signed keychain group does not require a shared filesystem.
        // SecItemAdd/Update is the runtime authority; metadata alone grants nothing.
        if let group = sharedKeychainGroup {
            try ConnectionKeychain.save(ServerConnection(endpoint: endpoint, token: token), group: group)
            return "공유 키체인으로 연결 설정을 저장했습니다."
        }
        if let store = sharedDefaults {
            store.set(endpoint, forKey: "serverURL"); store.set(token, forKey: "serverToken")
            return "App Group으로 연결 설정을 저장했습니다."
        }
        throw ConnectionKeychain.StorageError(status: -34018)
    }
    static func loadConnection() throws -> ServerConnection? {
        if let group = sharedKeychainGroup, let connection = try ConnectionKeychain.load(group: group) { return connection }
        guard let store = sharedDefaults, let endpoint = store.string(forKey: "serverURL") else { return nil }
        return ServerConnection(endpoint: endpoint, token: store.string(forKey: "serverToken") ?? "")
    }
    static var sharingDiagnostics: String {
        func display(_ groups: [String]?) -> String { groups.map { $0.isEmpty ? "없음" : $0.joined(separator: ", ") } ?? "읽지 못함" }
        return ["공통 서명 키체인: \(sharedKeychainGroup ?? "없음")", sharing.reason,
                "구성 그룹: \(configuredAppGroup)",
                "앱 서명 그룹: \(display(claims(hostBundle)))",
                "방송 확장 서명 그룹: \(display(claims(uploadBundle)))",
                "앱 프로필 그룹: \(display(profile(hostBundle)))",
                "방송 확장 프로필 그룹: \(display(profile(uploadBundle)))",
                "사용할 그룹: \(sharing.group ?? "없음")"].joined(separator: "\n")
    }
}
