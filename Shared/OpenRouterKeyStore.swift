import Foundation
import Security

/// The user's OpenRouter API key, kept in the Keychain inside the shared App
/// Group access group so the share extension can read what the host app saved.
/// No key → Little Dia stays fully on-device.
enum OpenRouterKeyStore {

    static let appGroup = "group.com.jonasleupe.ShareExperiment"
    private static let service = "openrouter.ai"
    private static let account = "api-key"

    /// Model used for web research and web-backed chat.
    static let model = "openai/gpt-5.6-luna"
    static let modelDisplayName = "GPT-5.6 Luna"

    static var hasKey: Bool { !(load()?.isEmpty ?? true) }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return remove() }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let update = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return true }
        var add = baseQuery
        attributes.forEach { add[$0.key] = $0.value }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func remove() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: appGroup,
        ]
    }
}
