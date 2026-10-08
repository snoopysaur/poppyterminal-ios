import Foundation
import Security
import PoppyKit

/// Guarda de segredo no Keychain. Nada disso entra no repositorio.
enum Keychain {
    static let service = "io.github.snoopysaur.poppyterminal"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Ajustes do usuario: URL https do servidor (UserDefaults), usuario e senha (Keychain).
@MainActor
final class AppSettings: ObservableObject {
    private static let urlKey = "serverURL"
    private static let userKey = "serverUser"
    private static let sessionKey = "serverSession"
    private static let passAccount = "web-password"

    @Published var serverURL: String
    @Published var user: String
    @Published var password: String
    @Published var session: String

    init() {
        serverURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        user = UserDefaults.standard.string(forKey: Self.userKey) ?? "tuios"
        password = Keychain.get(Self.passAccount) ?? ""
        session = UserDefaults.standard.string(forKey: Self.sessionKey) ?? ""
    }

    /// URL wss do /ws, ou nil se ainda nao configurado/invalido.
    var endpoint: URL? { ServerEndpoint.parse(serverURL, session: session) }

    var sessionValid: Bool { SessionName.isAcceptable(session) }

    func save() {
        UserDefaults.standard.set(serverURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.urlKey)
        UserDefaults.standard.set(user, forKey: Self.userKey)
        UserDefaults.standard.set(SessionName.normalize(session), forKey: Self.sessionKey)
        Keychain.set(password, account: Self.passAccount)
    }
}
