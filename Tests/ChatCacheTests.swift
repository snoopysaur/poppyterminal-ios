import XCTest
import PoppyKit
@testable import PoppyTerminal

final class ChatCacheTests: XCTestCase {
    private var dir: URL!
    private var cache: ChatCache!
    private let server = "http://exemplo.invalid:8080"
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("chatcache-\(UUID().uuidString)")
        cache = ChatCache(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func message(_ i: Int, text: String? = nil) -> ChatMessage {
        ChatMessage(id: "u\(i):0", cursor: "ab1f47251fd3fea5.\(i * 10)", ts: Int64(i),
                    role: i % 2 == 0 ? "user" : "assistant", kind: "text", text: text ?? "mensagem \(i)")
    }

    private func file(_ messages: [ChatMessage], at date: Date? = nil, window: String = "w1") -> ChatCacheFile {
        ChatCacheFile(v: 1, server: server, session: "s1", window: window,
                      conversationId: "ab1f47251fd3fea5", savedAt: date ?? t0, messages: messages)
    }

    func testNomeDoArquivoSao32HexEDependemDeServidorSessaoJanela() {
        let a = ChatCache.fileName(server: server, session: "s1", window: "w1")
        XCTAssertEqual(a.count, 32)
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertEqual(a, ChatCache.fileName(server: server, session: "s1", window: "w1"))
        XCTAssertNotEqual(a, ChatCache.fileName(server: server, session: "s1", window: "w2"))
        XCTAssertNotEqual(a, ChatCache.fileName(server: server, session: "s2", window: "w1"))
        XCTAssertNotEqual(a, ChatCache.fileName(server: "http://outro.invalid", session: "s1", window: "w1"))
    }

    func testSalvarECarregarIdaEVolta() throws {
        cache.save(file([message(1), message(2)]))
        let loaded = try XCTUnwrap(cache.load(server: server, session: "s1", window: "w1", now: t0.addingTimeInterval(60)))
        XCTAssertEqual(loaded.v, 1)
        XCTAssertEqual(loaded.conversationId, "ab1f47251fd3fea5")
        XCTAssertEqual(loaded.messages.map(\.id), ["u1:0", "u2:0"])
        XCTAssertEqual(loaded.savedAt.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(cache.load(server: server, session: "s1", window: "outra", now: t0))
    }

    func testGuardaSoAsUltimas200Mensagens() throws {
        cache.save(file((1...350).map { message($0) }))
        let loaded = try XCTUnwrap(cache.load(server: server, session: "s1", window: "w1", now: t0))
        XCTAssertEqual(loaded.messages.count, 200)
        XCTAssertEqual(loaded.messages.first?.id, "u151:0")
        XCTAssertEqual(loaded.messages.last?.id, "u350:0")
    }

    func testCortaAsMaisAntigasAte512KB() throws {
        let big = String(repeating: "x", count: 8000)
        cache.save(file((1...200).map { message($0, text: big) }))
        let url = cache.fileURL(server: server, session: "s1", window: "w1")
        let size = try XCTUnwrap(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThanOrEqual(size, 512 * 1024)
        let loaded = try XCTUnwrap(cache.load(server: server, session: "s1", window: "w1", now: t0))
        XCTAssertFalse(loaded.messages.isEmpty)
        XCTAssertLessThan(loaded.messages.count, 200)
        XCTAssertEqual(loaded.messages.last?.id, "u200:0", "fica com as mais novas")
        XCTAssertEqual(cache.totalBytes(), size)
    }

    func testExpiraEmSeteDiasEApagaOArquivo() throws {
        cache.save(file([message(1)]))
        let day: TimeInterval = 24 * 60 * 60
        XCTAssertNotNil(cache.load(server: server, session: "s1", window: "w1", now: t0.addingTimeInterval(7 * day - 1)))
        XCTAssertNil(cache.load(server: server, session: "s1", window: "w1", now: t0.addingTimeInterval(7 * day + 1)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL(server: server, session: "s1", window: "w1").path))
    }

    func testSweepApagaVencidoELixoEMantemOFresco() throws {
        cache.save(file([message(1)], at: t0, window: "velho"))
        cache.save(file([message(2)], at: t0.addingTimeInterval(6 * 86_400), window: "novo"))
        try Data("nao e json".utf8).write(to: dir.appendingPathComponent("lixo.json"))
        cache.sweep(now: t0.addingTimeInterval(8 * 86_400))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL(server: server, session: "s1", window: "velho").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("lixo.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.fileURL(server: server, session: "s1", window: "novo").path))
    }

    func testRemoveERemoveAll() {
        cache.save(file([message(1)], window: "a"))
        cache.save(file([message(1)], window: "b"))
        XCTAssertGreaterThan(cache.totalBytes(), 0)
        cache.remove(server: server, session: "s1", window: "a")
        XCTAssertNil(cache.load(server: server, session: "s1", window: "a", now: t0))
        XCTAssertNotNil(cache.load(server: server, session: "s1", window: "b", now: t0))
        cache.removeAll()
        XCTAssertEqual(cache.totalBytes(), 0)
        XCTAssertNil(cache.load(server: server, session: "s1", window: "b", now: t0))
    }

    func testPastaForaDoBackup() throws {
        cache.save(file([message(1)]))
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testVersaoDiferenteEDescartada() throws {
        cache.save(file([message(1)]))
        let url = cache.fileURL(server: server, session: "s1", window: "w1")
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"v\":1", with: "\"v\":99")
        try text.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(cache.load(server: server, session: "s1", window: "w1", now: t0))
    }
}
