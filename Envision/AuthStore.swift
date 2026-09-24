import Foundation
import Security
import Combine

/// Swift port of the frontend's `AuthContext` + localStorage/Keychain token store.
@MainActor
final class AuthStore: ObservableObject {
    @Published var user: User?
    @Published var isRestoring = true
    @Published private(set) var baseURL: URL

    let keychainAccount = "jellymax_token"
    private let serverKey = "jellymax_server_url"

    private(set) var api: JellymaxAPI!

    init() {
        let stored = UserDefaults.standard.string(forKey: serverKey) ?? "http://127.0.0.1:8097"
        baseURL = URL(string: stored) ?? URL(string: "http://127.0.0.1:8097")!
        api = JellymaxAPI(baseURL: baseURL, tokenProvider: { [weak self] in self?.token })
        restoreSession()
    }

    var isAdmin: Bool { user?.Policy?.IsAdministrator ?? false }
    var token: String? { Keychain.read(account: keychainAccount) }

    func setServer(_ url: URL) {
        baseURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: serverKey)
        api = JellymaxAPI(baseURL: url, tokenProvider: { [weak self] in self?.token })
        clearToken()
        user = nil
    }

    func restoreSession() {
        Task {
            defer { isRestoring = false }
            guard token != nil else { return }
            if let me = try? await api.me() {
                user = me
            }
            if user == nil { clearToken() }
        }
    }

    func login(username: String, password: String) async throws {
        let response = try await api.login(username: username, password: password)
        Keychain.write(account: keychainAccount, value: response.AccessToken)
        user = response.User
    }

    /// Store a session that was created elsewhere — a password login on another
    /// device, or a pairing code another Envision client approved.
    func adoptSession(token: String, user: User) {
        Keychain.write(account: keychainAccount, value: token)
        self.user = user
    }

    func logout() async {
        try? await api.logout()
        clearToken()
        user = nil
    }

    private func clearToken() {
        Keychain.delete(account: keychainAccount)
    }
}

enum Keychain {
    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
