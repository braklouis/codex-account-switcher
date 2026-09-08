import Foundation
import Security
import SwitcherCore

final class KeychainVault {
    private let service: String
    init(service: String = "local.codexaccounts.vault.v1") { self.service = service }
    private let account = "profiles"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    func load() throws -> [Profile] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SwitcherError("无法打开账号钥匙串（\(status)）。请解锁或允许访问后重试。")
        }
        guard let profiles = try? JSONDecoder().decode([Profile].self, from: data) else {
            throw SwitcherError("账号库格式无法读取，已保留原数据。")
        }
        return profiles
    }
    func save(_ profiles: [Profile]) throws {
        let data = try JSONEncoder().encode(profiles)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(request as CFDictionary, nil)
            guard added == errSecSuccess else { throw SwitcherError("保存到钥匙串失败（\(added)）。") }
        } else if status != errSecSuccess {
            throw SwitcherError("更新钥匙串失败（\(status)）。")
        }
    }
    func deleteTestVault() throws {
        guard service.hasPrefix("local.codexaccounts.selfcheck.") else { return }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SwitcherError("测试条目清理失败。") }
    }
}
