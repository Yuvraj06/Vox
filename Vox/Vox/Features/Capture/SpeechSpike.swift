import AVFoundation
import Observation
import Speech

/// Slice 0 spike: phone mic -> SpeechAnalyzer, live.
/// Goal: prove transcription keeps running while the app is in the background.
@Observable
final class SpeechSpike {
    var finalText = ""
    var partialText = ""
    var status = "Idle"
    var isRunning = false
    var appPhase = "active"
    var log: [String] = []

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    // MARK: Start

    func start() async {
        guard !isRunning else { return }
        finalText = ""
        partialText = ""
        status = "Asking for mic permission"

        guard await AVAudioApplication.requestRecordPermission() else {
            status = "Mic permission denied. Enable it in Settings."
            return
        }

        do {
            // 1. Pick a language and make sure the on-device model is installed.
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
                ?? Locale(identifier: "en-US")
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                status = "Downloading speech model"
                try await request.downloadAndInstall()
            }

            // 2. Audio session. Must be started while the app is in the foreground.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP])
            try session.setActive(true)
            observeInterruptions()

            // 3. Start the analyzer. We push audio into `stream`.
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                status = "No compatible audio format"
                return
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            try await analyzer.start(inputSequence: stream)
            self.analyzer = analyzer
            self.inputContinuation = continuation

            // 4. Read results as they arrive.
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        self?.handle(text: text, isFinal: result.isFinal)
                    }
                } catch {
                    self?.addLog("Results error: \(error.localizedDescription)")
                }
            }

            // 5. Mic -> converter -> analyzer.
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard let converter = BufferConverter(from: inputFormat, to: analyzerFormat) else {
                status = "Cannot convert mic audio"
                return
            }
            Self.installTap(on: engine.inputNode, format: inputFormat, converter: converter, continuation: continuation)
            engine.prepare()
            try engine.start()

            isRunning = true
            status = "Listening"
            addLog("Started (\(locale.identifier))")
        } catch {
            status = "Error: \(error.localizedDescription)"
            addLog("Start failed: \(error.localizedDescription)")
            await stop()
        }
    }

    // MARK: Stop

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        isRunning = false
        status = "Stopped"
        addLog("Stopped")
    }

    // MARK: Helpers

    private func handle(text: String, isFinal: Bool) {
        if isFinal {
            finalText += text + " "
            partialText = ""
            addLog("FINAL: \(text)")
        } else {
            partialText = text
        }
    }

    func addLog(_ message: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        log.insert("\(time) [\(appPhase)] \(message)", at: 0)
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated {
                self?.addLog("Audio interruption: \(type == .began ? "began" : "ended")")
            }
        }
    }

    /// Runs off the main actor. The tap callback happens on a real-time audio thread.
    private nonisolated static func installTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        converter: BufferConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let converted = converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
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
