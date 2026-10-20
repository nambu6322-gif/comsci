import Foundation

// Reads only metadata from this app and its own embedded extension. Parsing a
// profile does not grant rights: containerURL remains the runtime authority.
enum SigningGroups {
    static let entitlement = "com.apple.security.application-groups"
    static func groups(in dictionary: [String: Any]) -> [String] {
        (dictionary[entitlement] as? [String] ?? []).filter { $0.hasPrefix("group.") && !$0.contains("*") }
    }
    static func profileGroups(_ data: Data) -> [String]? { profileEntitlements(data).map(groups) }
    static func profileEntitlements(_ data: Data) -> [String: Any]? {
        guard data.count <= 4 * 1024 * 1024,
              let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let value = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
              let entitlements = value["Entitlements"] as? [String: Any] else { return nil }
        return entitlements
    }
    static func signedGroups(_ data: Data) -> [String]? { signedEntitlements(data).map(groups) }
    static func signedEntitlements(_ data: Data) -> [String: Any]? {
        guard data.count >= 32, word(data, 0) == 0xfeedfacf,
              let commands = word(data, 16), commands < 4096 else { return nil }
        var cursor = 32
        for _ in 0..<commands {
            guard let command = word(data, cursor), let size = word(data, cursor + 4), size >= 8,
                  Int(size) <= data.count - cursor else { return nil }
            if command == 0x1d {
                guard size >= 16, let offset = word(data, cursor + 8), let length = word(data, cursor + 12),
                      Int(offset) <= data.count, Int(length) <= data.count - Int(offset) else { return nil }
                return signatureGroups(data.subdata(in: Int(offset)..<(Int(offset) + Int(length))))
            }
            cursor += Int(size)
        }
        return nil
    }
    private static func signatureGroups(_ data: Data) -> [String: Any]? {
        guard word(data, 0, bigEndian: true) == 0xfade0cc0,
              let length = word(data, 4, bigEndian: true), Int(length) <= data.count,
              let count = word(data, 8, bigEndian: true), count < 1024,
              12 + Int(count) * 8 <= Int(length) else { return nil }
        for index in 0..<Int(count) {
            guard let kind = word(data, 12 + index * 8, bigEndian: true),
                  let offset = word(data, 16 + index * 8, bigEndian: true) else { return nil }
            if kind != 5 { continue }
            let start = Int(offset)
            guard start >= 12 + Int(count) * 8,
                  word(data, start, bigEndian: true) == 0xfade7171,
                  let blobLength = word(data, start + 4, bigEndian: true), blobLength >= 8,
                  start <= Int(length), Int(blobLength) <= Int(length) - start,
                  let value = try? PropertyListSerialization.propertyList(from: data.subdata(in: (start + 8)..<(start + Int(blobLength))), format: nil) as? [String: Any] else { return nil }
            return value
        }
        return nil
    }
    private static func word(_ data: Data, _ offset: Int, bigEndian: Bool = false) -> UInt32? {
        guard offset >= 0, offset <= data.count, data.count - offset >= 4 else { return nil }
        let bytes = Array(data[offset..<(offset + 4)])
        return (bigEndian ? bytes : Array(bytes.reversed())).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    struct Resolution {
        let group: String?
        let reason: String
    }
    static func resolve(configured: String, appClaims: [String]?, extensionClaims: [String]?, appProfile: [String]?, extensionProfile: [String]?, canAccess: (String) -> Bool) -> Resolution {
        guard let appClaims = appClaims, let extensionClaims = extensionClaims else {
            return Resolution(group: nil, reason: "앱 또는 방송 확장의 서명 권한 정보를 읽지 못했습니다.")
        }
        guard !appClaims.isEmpty, !extensionClaims.isEmpty else {
            return Resolution(group: nil, reason: "현재 서명에서 앱 또는 방송 확장의 App Group 권한이 빠져 있습니다. 권한을 포함하는 설치·서명이 필요합니다.")
        }
        var common = Set(appClaims).intersection(extensionClaims)
        guard !common.isEmpty else {
            return Resolution(group: nil, reason: "앱과 방송 확장의 App Group이 서로 다릅니다. 두 대상에 같은 공유 그룹을 포함해 서명해야 합니다.")
        }
        if let appProfile = appProfile { common.formIntersection(appProfile) }
        if let extensionProfile = extensionProfile { common.formIntersection(extensionProfile) }
        guard !common.isEmpty else {
            return Resolution(group: nil, reason: "서명에서 요구한 App Group을 설치 프로필이 허용하지 않습니다.")
        }
        // Both processes choose the same name, even when several groups exist.
        let selected = common.contains(configured) ? configured : common.sorted()[0]
        guard canAccess(selected) else {
            return Resolution(group: nil, reason: "공통 App Group은 있으나 iOS가 공유 폴더 접근을 허용하지 않았습니다. 설치 프로필과 서명 권한을 확인해야 합니다.")
        }
        return Resolution(group: selected, reason: selected == configured ? "공유 설정 권한을 확인했습니다." : "재서명된 공통 App Group을 확인했습니다.")
    }
}
