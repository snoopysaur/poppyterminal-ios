import XCTest
import UIKit
import PoppyKit
@testable import PoppyTerminal

final class PoppyTerminalTests: XCTestCase {
    func testFonteJetBrainsMonoNerdRegistrada() {
        XCTAssertNotNil(UIFont(name: Theme.fontRegular, size: 14), "UIAppFonts nao registrou a fonte")
    }

    func testPaletaMocha() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        Theme.background.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int((r * 255).rounded()), 0x1E)
        XCTAssertEqual(Int((g * 255).rounded()), 0x1E)
        XCTAssertEqual(Int((b * 255).rounded()), 0x2E)
        Theme.accent.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int((r * 255).rounded()), 0xCB)
    }

    func testPoppyKitLinkado() {
        XCTAssertEqual(Array(SipCodec.input("a")), [0x30, 0x61])
    }
}
