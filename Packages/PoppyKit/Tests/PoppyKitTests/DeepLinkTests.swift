import XCTest
@testable import PoppyKit

/// v0.4 S4: parser estrito do deep link do push e a rota `GET /api/v1/push/{id}`.
final class DeepLinkTests: XCTestCase {
    private let hex = "0123456789abcdef0123456789abcdef"

    func testLinkValidoVira32HexMinusculo() {
        XCTAssertEqual(DeepLink.parse("poppyterminal://inbox/\(hex)"), .inbox(pushID: hex))
        XCTAssertEqual(DeepLink.parse(URL(string: "poppyterminal://inbox/\(hex)")!), .inbox(pushID: hex))
    }

    /// Cada entrada abaixo e rejeitada. Controle negativo: afrouxar qualquer regra do parser
    /// (aceitar maiuscula, 33 caracteres, query...) deixa o respectivo caso vermelho.
    func testRejeitaTudoQueNaoSejaOFormatoExato() {
        let ruins: [String: String] = [
            "host diferente": "poppyterminal://sessions/\(hex)",
            "caminho extra": "poppyterminal://inbox/\(hex)/x",
            "barra final": "poppyterminal://inbox/\(hex)/",
            "sem id": "poppyterminal://inbox/",
            "sem barra": "poppyterminal://inbox",
            "maiuscula": "poppyterminal://inbox/\(hex.uppercased())",
            "uma maiuscula": "poppyterminal://inbox/A123456789abcdef0123456789abcdef",
            "31 chars": "poppyterminal://inbox/\(hex.dropLast())",
            "33 chars": "poppyterminal://inbox/\(hex)0",
            "nao hex": "poppyterminal://inbox/0123456789abcdef0123456789abcdeg",
            "ponto-ponto": "poppyterminal://inbox/../../etc/passwd",
            "ponto-ponto no lugar do id": "poppyterminal://inbox/..",
            "%2e%2e": "poppyterminal://inbox/%2e%2e",
            "id codificado": "poppyterminal://inbox/%30123456789abcdef0123456789abcdef",
            "query": "poppyterminal://inbox/\(hex)?x=1",
            "query vazia": "poppyterminal://inbox/\(hex)?",
            "fragmento": "poppyterminal://inbox/\(hex)#a",
            "usuario": "poppyterminal://user@inbox/\(hex)",
            "porta": "poppyterminal://inbox:80/\(hex)",
            "esquema errado": "https://inbox/\(hex)",
            "esquema maiusculo": "POPPYTERMINAL://inbox/\(hex)",
            "espaco": "poppyterminal://inbox/\(hex) ",
            "vazio": "",
            "longa": "poppyterminal://inbox/" + String(repeating: "a", count: 300),
            "longa com id valido no inicio": "poppyterminal://inbox/\(hex)" + String(repeating: "a", count: 200),
        ]
        for (nome, link) in ruins {
            XCTAssertNil(DeepLink.parse(link), "deveria rejeitar: \(nome)")
        }
    }

    func testIdDoPushNaoEhIdDeItem() {
        XCTAssertTrue(DeepLink.isValidPushID(hex))
        XCTAssertFalse(DeepLink.isValidPushID("17"))
        XCTAssertFalse(DeepLink.isValidPushID(hex.uppercased()))
    }

    // MARK: rota

    private func client(_ t: MockTransport) -> APIClient {
        APIClient(endpoints: Endpoints(serverURL: "https://exemplo.ts.net")!, authHeader: nil, transport: t)
    }

    func testUrlDaRotaPush() {
        let e = Endpoints(serverURL: "https://exemplo.ts.net")!
        XCTAssertEqual(e.push(id: hex)?.absoluteString, "https://exemplo.ts.net/api/v1/push/\(hex)")
        XCTAssertNil(e.push(id: "../x"))
        XCTAssertNil(e.push(id: hex.uppercased()))
        XCTAssertNil(e.push(id: hex + "0"))
    }

    func testPushDevolveOItemEFazGetNaRota() async throws {
        let t = MockTransport { _ in .init(status: 200, body: Data(#"{"inbox_id":"17"}"#.utf8)) }
        let target = try await client(t).push(id: hex)
        XCTAssertEqual(target, PushTarget(inboxId: "17"))
        XCTAssertEqual(t.requests.count, 1)
        XCTAssertEqual(t.requests.first?.httpMethod, "GET")
        XCTAssertEqual(t.requests.first?.url?.path, "/api/v1/push/\(hex)")
    }

    /// 404 (servidor antigo, expirado) e resultado normal: nil, sem lancar. Controle: 500 lanca.
    func test404EhResultadoNormalEOutrosErrosSobem() async throws {
        let nf = MockTransport { _ in
            .init(status: 404, body: Data(#"{"error":{"code":"not_found","message":"push desconhecido ou expirado"}}"#.utf8))
        }
        let none = try await client(nf).push(id: hex)
        XCTAssertNil(none)
        let velho = MockTransport { _ in .init(status: 404, body: Data("404 page not found".utf8)) }
        let noneVelho = try await client(velho).push(id: hex)
        XCTAssertNil(noneVelho, "servidor antigo responde 404 sem JSON")
        let boom = MockTransport { _ in .init(status: 500, body: Data("{}".utf8)) }
        do {
            _ = try await client(boom).push(id: hex)
            XCTFail("500 deveria lancar")
        } catch {}
    }

    func testIdInvalidoNemSaiDoCliente() async {
        let t = MockTransport { _ in .init(status: 200, body: Data(#"{"inbox_id":"17"}"#.utf8)) }
        do {
            _ = try await client(t).push(id: "../../x")
            XCTFail("deveria lancar")
        } catch {}
        XCTAssertTrue(t.requests.isEmpty, "id invalido nao faz requisicao")
    }

    func testInboxIdMalformadoDoServidorEhIgnorado() async throws {
        let t = MockTransport { _ in .init(status: 200, body: Data(#"{"inbox_id":"../x"}"#.utf8)) }
        let r = try await client(t).push(id: hex)
        XCTAssertNil(r)
    }
}
