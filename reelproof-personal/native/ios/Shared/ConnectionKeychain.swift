import Foundation
import Security

struct ServerConnection: Codable {
    let endpoint: String
    let token: String
    var sessionID: String? = nil
    var valid: Bool {
        guard let url = URL(string: endpoint) else { return false }
        return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }
}

enum ConnectionKeychain {
    struct StorageError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "키체인 접근 상태 \(status). 앱과 방송 확장에 같은 keychain-access-groups 서명이 필요합니다."
        }
    }
    private static func query(_ group: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.reelproof.connection.v1",
         kSecAttrAccount as String: "broadcast-connection",
         kSecAttrAccessGroup as String: group,
         kSecAttrSynchronizable as String: false]
    }
    static func save(_ connection: ServerConnection, group: String) throws {
        guard connection.valid else { throw StorageError(status: errSecParam) }
        let data = try JSONEncoder().encode(connection)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query(group) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(group).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError(status: status) }
        guard try load(group: group)?.endpoint == connection.endpoint else { throw StorageError(status: errSecDecode) }
    }
    static func load(group: String) throws -> ServerConnection? {
        var request = query(group)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError(status: status) }
        guard let data = result as? Data else { throw StorageError(status: errSecDecode) }
        let connection = try JSONDecoder().decode(ServerConnection.self, from: data)
        guard connection.valid else { throw StorageError(status: errSecParam) }
        return connection
    }
}
