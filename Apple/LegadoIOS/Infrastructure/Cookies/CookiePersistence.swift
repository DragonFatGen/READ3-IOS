import Foundation
import Security

protocol CookiePersistence: Sendable {
    func load() async throws -> Data?
    func save(_ data: Data) async throws
    func remove() async throws
}

enum KeychainCookiePersistenceError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

actor KeychainCookiePersistence: CookiePersistence {
    private let service: String
    private let account: String

    init(
        service: String = "com.read3.legadoios.cookies",
        account: String = "shared-cookie-session"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainCookiePersistenceError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainCookiePersistenceError.invalidData
        }
        return data
    }

    func save(_ data: Data) throws {
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainCookiePersistenceError.unexpectedStatus(updateStatus)
        }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCookiePersistenceError.unexpectedStatus(addStatus)
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCookiePersistenceError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
