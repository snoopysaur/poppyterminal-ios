import Foundation
import PoppyKit

/// Persistencia dos snippets (a barra de teclas do terminal le a mesma chave).
enum SnippetStorage {
    static let key = "poppy.snippets.v1"

    static func load(_ defaults: UserDefaults = .standard) -> [Snippet] {
        SnippetList.decode(defaults.data(forKey: key))
    }

    static func save(_ list: [Snippet], _ defaults: UserDefaults = .standard) {
        if let data = SnippetList.encode(list) { defaults.set(data, forKey: key) }
    }
}
