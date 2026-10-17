import XCTest
import UIKit
import PoppyKit
@testable import PoppyTerminal

final class PoppyTerminalTests: XCTestCase {
    func testFonteJetBrainsMonoNerdRegistrada() {
        XCTAssertNotNil(UIFont(name: Theme.fontRegular, size: 14), "UIAppFonts nao registrou a fonte")
    }

    func testPaletaGuild() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        Theme.background.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int((r * 255).rounded()), 0x1B)
        XCTAssertEqual(Int((g * 255).rounded()), 0x16)
        XCTAssertEqual(Int((b * 255).rounded()), 0x12)
        Theme.accent.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int((r * 255).rounded()), 0xE8)
    }

    func testVersaoDoApp() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(version, "0.5.0")
    }

    /// ATS: NSAllowsArbitraryLoads nunca; NSAllowsLocalNetworking so existe em Debug (E2E).
    func testAtsSemCarregamentoArbitrario() {
        let ats = Bundle.main.infoDictionary?["NSAppTransportSecurity"] as? [String: Any]
        XCTAssertNil(ats?["NSAllowsArbitraryLoads"])
        #if DEBUG
        XCTAssertEqual(ats?["NSAllowsLocalNetworking"] as? Bool, true)
        #else
        XCTAssertNil(ats?["NSAllowsLocalNetworking"])
        #endif
    }

    func testPoppyKitLinkado() {
        XCTAssertEqual(Array(SipCodec.input("a")), [0x30, 0x61])
    }
}
