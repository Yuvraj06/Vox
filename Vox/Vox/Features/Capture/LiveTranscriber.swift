import AVFoundation
import Observation
import Speech

/// Phone mic -> SpeechAnalyzer, live. Built for push to talk:
/// `prepare()` once ahead of time, then `start()` and `stop()` for each recording.
@Observable
final class LiveTranscriber {
    enum TranscriberError: LocalizedError {
        case micDenied, noAudioFormat, cannotConvert

        var errorDescription: String? {
            switch self {
            case .micDenied: "Vox needs the microphone. Turn it on in Settings > Vox."
            case .noAudioFormat, .cannotConvert: "The microphone isn't working right now."
            }
        }
    }

    /// Finished text plus the words still being worked out.
    var text: String { (finalText + partialText).trimmingCharacters(in: .whitespaces) }
    /// Mic loudness from 0 to 1, for the glow ring.
    private(set) var level: Float = 0

    private var finalText = ""
    private var partialText = ""
    private var locale: Locale?
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// Asks for the mic and makes sure the speech model is installed.
    func prepare() async throws {
        guard locale == nil else { return }
        guard await AVAudioApplication.requestRecordPermission() else { throw TranscriberError.micDenied }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en-US")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [Self.transcriber(locale)]) {
            try await request.downloadAndInstall()
        }
        self.locale = locale
    }

    func start() async throws {
        try await prepare()
        guard let locale else { return }
        finalText = ""
        partialText = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)

        let transcriber = Self.transcriber(locale)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriberError.noAudioFormat
        }
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let converter = BufferConverter(from: inputFormat, to: analyzerFormat) else {
            throw TranscriberError.cannotConvert
        }

        // Start the mic first. The stream holds the audio until the analyzer is ready,
        // so the first word isn't cut off.
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation
        Self.installTap(on: engine.inputNode, format: inputFormat, converter: converter, continuation: continuation) { [weak self] level in
            let target = self
            Task { @MainActor in target?.level = level }
        }
        engine.prepare()
        try engine.start()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.handle(String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {}
        }
        try await analyzer.start(inputSequence: stream)
    }

    /// Stops listening and returns everything that was said.
    func stop() async -> String {
        stopMic()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        finish()
        return text
    }

    /// Stops listening and throws the words away.
    func cancel() async {
        stopMic()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        finish()
        finalText = ""
        partialText = ""
    }

    // MARK: Helpers

    private static func transcriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    private func handle(_ text: String, isFinal: Bool) {
        if isFinal {
            finalText += text + " "
            partialText = ""
        } else {
            partialText = text
        }
    }

    private func stopMic() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        level = 0
    }

    private func finish() {
        resultsTask = nil
        analyzer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Runs off the main actor. The tap callback happens on a real-time audio thread.
    private nonisolated static func installTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        converter: BufferConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            onLevel(loudness(buffer))
            guard let converted = converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    /// Rough loudness (RMS in decibels, mapped to 0...1).
    private nonisolated static func loudness(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 50) / 40, 0), 1)
    }
}

/// Converts mic buffers to the format SpeechAnalyzer wants (usually 16 kHz mono).
nonisolated final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.converter = converter
        self.outputFormat = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
