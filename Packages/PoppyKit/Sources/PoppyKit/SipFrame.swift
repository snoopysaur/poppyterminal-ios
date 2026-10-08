import Foundation

/// Tipos de quadro do protocolo sip (primeiro byte ASCII do quadro binario).
/// Fonte do protocolo: handlers.go do servidor (constantes Msg*).
public enum SipMessageType: UInt8, Sendable, CaseIterable {
    case input = 0x30         // '0' entrada de terminal (cliente -> servidor)
    case output = 0x31        // '1' saida de terminal (servidor -> cliente)
    case resize = 0x32        // '2' redimensionar (JSON)
    case ping = 0x33          // '3'
    case pong = 0x34          // '4'
    case title = 0x35         // '5' titulo da janela
    case options = 0x36       // '6' opcoes de configuracao
    case close = 0x37         // '7' sessao fechada (servidor -> cliente)
    case kittyKeyboard = 0x38 // '8' flags do protocolo de teclado kitty
}

/// Corpo JSON do quadro de resize.
public struct SipResize: Codable, Equatable, Sendable {
    public var cols: Int
    public var rows: Int
    public var widthPx: Int
    public var heightPx: Int

    public init(cols: Int, rows: Int, widthPx: Int = 0, heightPx: Int = 0) {
        self.cols = cols
        self.rows = rows
        self.widthPx = widthPx
        self.heightPx = heightPx
    }
}

/// Um quadro sip decodificado: tipo + payload.
public struct SipFrame: Equatable, Sendable {
    public var type: SipMessageType
    public var payload: Data

    public init(type: SipMessageType, payload: Data = Data()) {
        self.type = type
        self.payload = payload
    }
}

public enum SipCodecError: Error, Equatable {
    case empty
    case unknownType(UInt8)
}

public enum SipCodec {
    /// Serializa: [tipo][payload].
    public static func encode(_ frame: SipFrame) -> Data {
        var data = Data([frame.type.rawValue])
        data.append(frame.payload)
        return data
    }

    public static func decode(_ data: Data) throws -> SipFrame {
        guard let first = data.first else { throw SipCodecError.empty }
        guard let type = SipMessageType(rawValue: first) else {
            throw SipCodecError.unknownType(first)
        }
        return SipFrame(type: type, payload: Data(data.dropFirst()))
    }

    public static func input(_ bytes: Data) -> Data {
        encode(SipFrame(type: .input, payload: bytes))
    }

    public static func input(_ text: String) -> Data {
        input(Data(text.utf8))
    }

    public static func resize(_ size: SipResize) throws -> Data {
        let json = try JSONEncoder().encode(size)
        return encode(SipFrame(type: .resize, payload: json))
    }

    public static func ping() -> Data { encode(SipFrame(type: .ping)) }
    public static func pong() -> Data { encode(SipFrame(type: .pong)) }

    public static func decodeResize(_ frame: SipFrame) throws -> SipResize {
        try JSONDecoder().decode(SipResize.self, from: frame.payload)
    }
}
