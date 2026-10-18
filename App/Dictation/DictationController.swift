import AVFoundation
import Foundation
import Observation
import Speech
import UIKit

/// Ditado por voz com o reconhecimento de fala do proprio iOS (framework Speech). Sem servico de
/// terceiros. Quando o aparelho sabe reconhecer pt-BR sem internet, o ditado fica 100% no aparelho;
/// senao o iOS pode mandar o audio para a Apple, e a tela avisa.
/// O ditado NUNCA envia nada: so entrega o texto para a pessoa revisar.
@MainActor @Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        /// Sem permissao de microfone ou de fala.
        case denied
        /// Reconhecimento de pt-BR indisponivel agora.
        case unavailable
    }

    private(set) var state: State = .idle
    /// Texto reconhecido ate agora (substitui a cada resultado parcial).
    private(set) var transcript = ""
    /// `true` quando o reconhecimento acontece so no aparelho.
    private(set) var onDevice = false

    var isListening: Bool { state == .listening || state == .starting }

    /// Muda a cada `start()`: um `start()` antigo que acorda depois de um `stop()` nao faz mais nada.
    @ObservationIgnored private var startToken = 0
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var box: SpeechRequestBox?

    init() {}

    /// Muda o estado e, para o VoiceOver, avisa em voz alta o que mudou (ouvindo, sem permissao...).
    private func update(_ new: State) {
        let old = state
        state = new
        guard old != new else { return }
        let message: String?
        switch new {
        case .listening: message = "Ouvindo."
        case .denied: message = "Sem permissão para o ditado. Libere em Ajustes do iPhone."
        case .unavailable: message = "Ditado indisponível agora em português."
        case .idle: message = (old == .listening || old == .starting) ? "Ditado parado." : nil
        case .starting: message = nil
        }
        if let message { UIAccessibility.post(notification: .announcement, argument: message) }
    }

    func toggle() {
        if isListening { stop() } else { Task { await start() } }
    }

    func start() async {
        guard !isListening else { return }
        update(.starting)
        startToken += 1
        let myToken = startToken
        transcript = ""
        // A pessoa pode ter parado durante o pedido de permissao (stop() poe o estado em idle): se o
        // estado deixou de ser `.starting`, nada mais acontece (antes o ditado "ressuscitava" sozinho).
        let speechOK = await SpeechPermission.requestSpeech()
        guard state == .starting, myToken == startToken else { return }
        guard speechOK else { update(.denied); return }
        let micOK = await SpeechPermission.requestMicrophone()
        guard state == .starting, myToken == startToken else { return }
        guard micOK else { update(.denied); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR")), recognizer.isAvailable else {
            update(.unavailable)
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                onDevice = true
            } else {
                onDevice = false
            }
            let box = SpeechRequestBox(request)
            self.box = box

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: SpeechCallbacks.tap(box))
            engine.prepare()
            try engine.start()
            self.engine = engine

            task = recognizer.recognitionTask(with: request, resultHandler: SpeechCallbacks.result { [weak self] text, isFinal, failed in
                Task { @MainActor in self?.received(text: text, isFinal: isFinal, failed: failed) }
            })
            update(.listening)
        } catch {
            cleanup()
            update(.unavailable)
        }
    }

    func stop() {
        guard isListening else { return }
        cleanup()
        update(.idle)
    }

    private func received(text: String?, isFinal: Bool, failed: Bool) {
        guard state == .listening else { return }
        if let text { transcript = text }
        if isFinal || failed {
            cleanup()
            update(.idle)
        }
    }

    private func cleanup() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        box?.finish()
        box = nil
        task?.finish()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Pedidos de permissao (microfone e fala). Fora do ator principal de proposito: o iOS chama os
/// retornos em outra fila.
enum SpeechPermission {
    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

/// Guarda o pedido de reconhecimento para o retorno do audio (que roda em outra fila).
final class SpeechRequestBox: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
    func finish() { request.endAudio() }
}

/// Retornos criados fora do ator principal (o iOS os chama em filas de audio/reconhecimento).
enum SpeechCallbacks {
    static func tap(_ box: SpeechRequestBox) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in box.append(buffer) }
    }

    static func result(_ onEvent: @escaping @Sendable (String?, Bool, Bool) -> Void)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            onEvent(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}

/// Texto do campo depois de ditar: o que ja estava escrito mais o ditado, com um espaco no meio.
enum DictationText {
    static func merge(base: String, dictated: String) -> String {
        let spoken = dictated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return base }
        if base.isEmpty { return spoken }
        let sep = base.hasSuffix(" ") || base.hasSuffix("\n") ? "" : " "
        return base + sep + spoken
    }

    /// No terminal o texto vai sem Enter e numa linha so (quebra de linha viraria comando).
    static func forTerminal(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
