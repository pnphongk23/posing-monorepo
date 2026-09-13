import Foundation
import Security

/// Matches KMP KeychainTokenStorage: service `com.aipose.session`, account `backend-session-token`.
final class KeychainTokenStorage: TokenStoring, @unchecked Sendable {
    private let service: String
    private let account: String
    private let lock = NSLock()
    private var sessionCache: SessionCredentials?

    init(service: String = "com.aipose.session", account: String = "backend-session-token") {
        self.service = service
        self.account = account
    }

    func saveCredentials(_ credentials: SessionCredentials) {
        lock.lock()
        sessionCache = credentials
        lock.unlock()
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let query = identityQuery() as CFDictionary
        SecItemDelete(query)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    func loadCredentials() -> SessionCredentials? {
        lock.lock()
        if let cached = sessionCache {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let credentials = try? JSONDecoder().decode(SessionCredentials.self, from: data) else {
            return nil
        }
        lock.lock()
        sessionCache = credentials
        lock.unlock()
        return credentials
    }

    func clearCredentials() {
        lock.lock()
        sessionCache = nil
        lock.unlock()
        SecItemDelete(identityQuery() as CFDictionary)
    }

    private func identityQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
