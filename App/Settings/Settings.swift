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
    private static let passAccount = "web-password"

    @Published var serverURL: String
    @Published var user: String
    @Published var password: String
    /// Endereco salvo (so muda em `save()`); `isConfigured` olha para ele.
    @Published private(set) var savedURL: String
    private var savedUser: String
    private var savedPassword: String

    init() {
        let url = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        let usr = UserDefaults.standard.string(forKey: Self.userKey) ?? "tuios"
        let pass = Keychain.get(Self.passAccount) ?? ""
        serverURL = url
        savedURL = url
        user = usr
        savedUser = usr
        password = pass
        savedPassword = pass
    }

    /// Endereco do campo e valido (https, ou http so em loopback).
    var urlValid: Bool { Endpoints(serverURL: serverURL) != nil }

    /// Ja existe um endereco salvo e valido.
    var isConfigured: Bool { Endpoints(serverURL: savedURL) != nil }

    /// Ha mudanca nao salva nos campos.
    var hasChanges: Bool {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines) != savedURL
            || user != savedUser || password != savedPassword
    }

    func save() {
        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(url, forKey: Self.urlKey)
        UserDefaults.standard.set(user, forKey: Self.userKey)
        Keychain.set(password, account: Self.passAccount)
        serverURL = url
        savedURL = url
        savedUser = user
        savedPassword = password
    }

    /// Entrega os ajustes salvos ao `ServerStore` (conecta ou reconecta).
    func apply(to store: ServerStore) {
        store.configure(serverURL: savedURL, user: savedUser, password: savedPassword)
    }
}
