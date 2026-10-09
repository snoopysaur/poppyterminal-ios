import XCTest
@testable import PoppyKit

final class F1Tests: XCTestCase {
    func testEndpointParse() {
        XCTAssertEqual(ServerEndpoint.parse("https://exemplo.ts.net")?.absoluteString, "wss://exemplo.ts.net/ws")
        XCTAssertEqual(ServerEndpoint.parse("exemplo.ts.net/")?.absoluteString, "wss://exemplo.ts.net/ws")
        XCTAssertEqual(ServerEndpoint.parse("https://exemplo.ts.net/ws")?.absoluteString, "wss://exemplo.ts.net/ws")
        XCTAssertEqual(ServerEndpoint.parse("https://exemplo.ts.net:8443/x?a=1")?.absoluteString, "wss://exemplo.ts.net:8443/x/ws")
        XCTAssertNil(ServerEndpoint.parse("http://exemplo.ts.net"))
        XCTAssertNil(ServerEndpoint.parse("   "))
    }

    func testBasicAuth() {
        XCTAssertEqual(BasicAuth.header(user: "tuios", password: "x"), "Basic dHVpb3M6eA==")
    }

    func testReconnectBackoff() {
        let p = ReconnectPolicy()
        XCTAssertEqual((0..<7).map { p.delay(forAttempt: $0) }, [1, 2, 4, 8, 16, 30, 30])
        XCTAssertEqual(p.delay(forAttempt: 999), 30)
    }

    func testFailureClassify() {
        XCTAssertEqual(ConnectionFailure.classify(urlErrorCode: -1003), .networkUnreachable)
        XCTAssertEqual(ConnectionFailure.classify(urlErrorCode: -1011), .denied)
        XCTAssertEqual(ConnectionFailure.classify(urlErrorCode: -999), .other)
    }

    func testStickyCtrlOnce() {
        var m = StickyModifiers()
        m.tapCtrl()
        XCTAssertEqual(m.apply(to: [0x63]), [0x03])
        XCTAssertEqual(m.apply(to: [0x63]), [0x63])
    }

    func testStickyAltAndLock() {
        var m = StickyModifiers()
        m.tapAlt(); m.tapAlt()
        XCTAssertEqual(m.apply(to: [0x78]), [0x1B, 0x78])
        XCTAssertEqual(m.apply(to: [0x78]), [0x1B, 0x78])
        m.tapAlt()
        XCTAssertEqual(m.apply(to: [0x78]), [0x78])
    }

    func testBarKeys() {
        XCTAssertEqual(BarKey.altEsc.bytes(), [0x1B, 0x1B])
        XCTAssertEqual(BarKey.up.bytes(), [0x1B, 0x5B, 0x41])
        XCTAssertEqual(BarKey.leader.bytes(), [0x1C])
        XCTAssertNil(BarKey.ctrl.bytes())
    }

    func testResizeFrame() throws {
        let d = try SipCodec.resize(SipResize(cols: 50, rows: 20, widthPx: 400, heightPx: 600))
        XCTAssertEqual(d.first, 0x32)
        let f = try SipCodec.decode(d)
        XCTAssertEqual(try SipCodec.decodeResize(f).cols, 50)
    }

    func testSessionName() {
        XCTAssertTrue(SessionName.isAcceptable(""))
        XCTAssertTrue(SessionName.isAcceptable("  "))
        XCTAssertTrue(SessionName.isAcceptable("poppy_1-A"))
        XCTAssertTrue(SessionName.isAcceptable(String(repeating: "a", count: 32)))
        XCTAssertFalse(SessionName.isAcceptable(String(repeating: "a", count: 33)))
        XCTAssertFalse(SessionName.isAcceptable("a b"))
        XCTAssertFalse(SessionName.isAcceptable("a/b"))
        XCTAssertFalse(SessionName.isAcceptable("sess\u{00E3}o"))
        XCTAssertFalse(SessionName.isAcceptable("a&b=c"))
    }

    func testEndpointWithSession() {
        XCTAssertEqual(ServerEndpoint.parse("https://exemplo.ts.net", session: "dev")?.absoluteString,
                       "wss://exemplo.ts.net/ws?session=dev")
        XCTAssertEqual(ServerEndpoint.parse("https://exemplo.ts.net/ws?x=1", session: " dev ")?.absoluteString,
                       "wss://exemplo.ts.net/ws?session=dev")
        XCTAssertEqual(ServerEndpoint.parse("https://exemplo.ts.net", session: "")?.absoluteString,
                       "wss://exemplo.ts.net/ws")
        XCTAssertNil(ServerEndpoint.parse("https://exemplo.ts.net", session: "a b"))
        XCTAssertNil(ServerEndpoint.parse("https://exemplo.ts.net", session: "x&y"))
    }
}

final class AgeLabelTests: XCTestCase {
    func testCompactAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func age(_ secs: Double) -> String { AgeLabel.text(since: now.addingTimeInterval(-secs), now: now) }
        XCTAssertEqual(age(0), "agora")
        XCTAssertEqual(age(59), "agora")
        XCTAssertEqual(age(60), "1 min")
        XCTAssertEqual(age(13 * 60 + 44), "13 min")
        XCTAssertEqual(age(3600), "1 h")
        XCTAssertEqual(age(86_400 * 3 + 5), "3 d")
        XCTAssertEqual(age(-30), "agora") // relogio do servidor adiantado
    }
}
