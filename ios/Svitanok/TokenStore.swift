import Foundation
import Security

enum TokenStore {
    private static let service = "ua.semmyx.svitanok.alerts-token"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    static func validated(_ value: String) throws -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...512).contains(token.utf8.count), token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw AlertsAPIError.invalidToken
        }
        return token
    }
    static func read(account: String = "alerts-in-ua") throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw AlertsAPIError.keychain }
        return value
    }
    static func save(_ value: String, account: String = "alerts-in-ua") throws {
        let token = try validated(value)
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account); attributes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw AlertsAPIError.keychain }
        } else if status != errSecSuccess { throw AlertsAPIError.keychain }
    }
    static func delete(account: String = "alerts-in-ua") throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AlertsAPIError.keychain }
    }
}
