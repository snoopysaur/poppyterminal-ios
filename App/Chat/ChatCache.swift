import Foundation
import CryptoKit
import PoppyKit

/// Conteudo de um arquivo de cache (uma janela). So guarda a saida JA redigida do servidor.
struct ChatCacheFile: Codable, Sendable {
    var v: Int
    var server: String
    var session: String
    var window: String
    var conversationId: String
    var savedAt: Date
    var messages: [ChatMessage]
}

/// Cache offline leve do chat (contrato §7): `Library/Caches/PoppyChat/<hash>.json`.
/// Ultimas 200 mensagens, ate 512 KB, validade de 7 dias, fora do backup.
/// Rascunho e mensagem local "enviando" nunca entram aqui.
struct ChatCache: Sendable {
    static let formatVersion = 1
    static let maxMessages = 200
    static let maxBytes = 512 * 1024
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    static let shared = ChatCache(directory: defaultDirectory)

    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PoppyChat", isDirectory: true)
    }

    let directory: URL

    init(directory: URL) { self.directory = directory }

    // MARK: nome do arquivo

    /// Os 32 primeiros hex de SHA256("<base>|<sessao>|<janela>").
    static func fileName(server: String, session: String, window: String) -> String {
        let digest = SHA256.hash(data: Data("\(server)|\(session)|\(window)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(32))
    }

    func fileURL(server: String, session: String, window: String) -> URL {
        directory.appendingPathComponent(Self.fileName(server: server, session: session, window: window) + ".json")
    }

    // MARK: leitura

    /// nil se nao existe, esta ilegivel, e de outra janela/versao ou passou de 7 dias
    /// (nos casos ruins o arquivo e apagado).
    func load(server: String, session: String, window: String, now: Date = .now) -> ChatCacheFile? {
        let url = fileURL(server: server, session: session, window: window)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let file = try? Self.decoder.decode(ChatCacheFile.self, from: data),
              file.v == Self.formatVersion,
              file.server == server, file.session == session, file.window == window,
              !Self.isExpired(file.savedAt, now: now) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return file
    }

    // MARK: escrita

    /// Corta para as ultimas 200 mensagens e, se passar de 512 KB, descarta as mais antigas ate caber.
    func save(_ file: ChatCacheFile) {
        var file = file
        file.v = Self.formatVersion
        file.messages = Self.trimmed(file.messages, template: file)
        guard let data = try? Self.encoder.encode(file) else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            var dir = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
            var url = fileURL(server: file.server, session: file.session, window: file.window)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try? url.setResourceValues(values)
        } catch {
            // Cache e so otimizacao: falhar em silencio.
        }
    }

    func remove(server: String, session: String, window: String) {
        try? FileManager.default.removeItem(at: fileURL(server: server, session: session, window: window))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Apaga o que passou de 7 dias e o que nao consegue ser lido. Roda na abertura do app.
    func sweep(now: Date = .now) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        struct Header: Decodable { var v: Int; var savedAt: Date }
        for url in urls {
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let h = try? Self.decoder.decode(Header.self, from: data),
                  h.v == Self.formatVersion,
                  !Self.isExpired(h.savedAt, now: now) else {
                try? fm.removeItem(at: url)
                continue
            }
        }
    }

    /// Tamanho atual do cache em disco (para Ajustes).
    func totalBytes() -> Int {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return urls.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: interno

    static func isExpired(_ savedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(savedAt) > maxAge
    }

    /// As ultimas `maxMessages` que, juntas com o cabecalho, cabem em `maxBytes`.
    static func trimmed(_ messages: [ChatMessage], template: ChatCacheFile) -> [ChatMessage] {
        var kept = Array(messages.suffix(maxMessages))
        var head = template
        head.messages = []
        let overhead = (try? encoder.encode(head).count) ?? 512
        var total = overhead
        var firstIndex = kept.count
        for (i, m) in kept.enumerated().reversed() {
            let size = ((try? encoder.encode(m).count) ?? 0) + 1 // virgula
            if total + size > maxBytes { break }
            total += size
            firstIndex = i
        }
        kept = Array(kept[firstIndex...])
        // Confere o total real e corta mais, se a estimativa ficou curta.
        while !kept.isEmpty {
            var f = template
            f.messages = kept
            if let n = try? encoder.encode(f).count, n > maxBytes { kept.removeFirst() } else { break }
        }
        return kept
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
