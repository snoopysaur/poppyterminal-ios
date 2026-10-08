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
}
