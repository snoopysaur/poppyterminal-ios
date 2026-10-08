import Foundation
import Testing
@testable import PoppyKit

@Suite struct SipCodecTests {
    @Test func tiposSaoOsCaracteresAscii() {
        #expect(SipMessageType.input.rawValue == UInt8(ascii: "0"))
        #expect(SipMessageType.output.rawValue == UInt8(ascii: "1"))
        #expect(SipMessageType.resize.rawValue == UInt8(ascii: "2"))
        #expect(SipMessageType.ping.rawValue == UInt8(ascii: "3"))
        #expect(SipMessageType.pong.rawValue == UInt8(ascii: "4"))
        #expect(SipMessageType.title.rawValue == UInt8(ascii: "5"))
        #expect(SipMessageType.options.rawValue == UInt8(ascii: "6"))
        #expect(SipMessageType.close.rawValue == UInt8(ascii: "7"))
        #expect(SipMessageType.kittyKeyboard.rawValue == UInt8(ascii: "8"))
    }

    @Test func entradaTemPrefixoZero() {
        let data = SipCodec.input("ls\r")
        #expect(Array(data) == [0x30] + Array("ls\r".utf8))
    }

    @Test func roundTripDeTodosOsTipos() throws {
        for type in SipMessageType.allCases {
            let frame = SipFrame(type: type, payload: Data([1, 2, 3]))
            #expect(try SipCodec.decode(SipCodec.encode(frame)) == frame)
        }
    }

    @Test func resizeVaiComoJson() throws {
        let data = try SipCodec.resize(SipResize(cols: 80, rows: 24, widthPx: 640, heightPx: 480))
        #expect(data.first == UInt8(ascii: "2"))
        let frame = try SipCodec.decode(data)
        let obj = try JSONSerialization.jsonObject(with: frame.payload) as? [String: Int]
        #expect(obj == ["cols": 80, "rows": 24, "widthPx": 640, "heightPx": 480])
        #expect(try SipCodec.decodeResize(frame) == SipResize(cols: 80, rows: 24, widthPx: 640, heightPx: 480))
    }

    @Test func pingPong() {
        #expect(Array(SipCodec.ping()) == [0x33])
        #expect(Array(SipCodec.pong()) == [0x34])
    }

    @Test func quadroVazioEInvalido() {
        #expect(throws: SipCodecError.empty) { try SipCodec.decode(Data()) }
        #expect(throws: SipCodecError.unknownType(0x7A)) { try SipCodec.decode(Data([0x7A])) }
    }

    @Test func sessaoFechadaSemPayload() throws {
        let frame = try SipCodec.decode(Data([0x37]))
        #expect(frame.type == .close)
        #expect(frame.payload.isEmpty)
    }
}
