import AVFoundation
import Foundation
import GeraniaCore

@MainActor
public final class LiveAudioIO {
    public var onAudio: (@Sendable (Data) -> Void)?
    public var onLevel: (@Sendable (Double) -> Void)?
    public var onPlaybackStarted: (@Sendable () -> Void)?
    public var onPlaybackDrained: (@Sendable () -> Void)?
    public var onError: (@Sendable (LiveError) -> Void)?

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playFormat: AVAudioFormat?
    private var pendingBuffers = 0
    private var isPlaying = false
    private var running = false
    private var echoMode: LiveEchoMode = .automatic
    private var loggedFirstChunk = false
    private var uplinkEnabled = true
    private var configurationObserver: NSObjectProtocol?

    public init() {}

    public var isRunning: Bool {
        running
    }

    /// Starts the audio, falling back to half-duplex when voice processing is unavailable.
    @discardableResult
    public func startWithFallback(echoMode: LiveEchoMode = .automatic) async throws -> LiveEchoMode {
        do {
            try start(echoMode: echoMode)
            return echoMode
        } catch {
            guard echoMode == .automatic else {
                throw error
            }
            Log.voice.error(
                "live: echo cancellation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            throw LiveError.cancelled
        }
        try start(echoMode: .halfDuplex)
        return .halfDuplex
    }

    public func start(echoMode: LiveEchoMode = .automatic) throws {
        guard !running else {
            return
        }
        let engine = AVAudioEngine()
        var started = false
        defer {
            if !started {
                if engine.inputNode.isVoiceProcessingEnabled {
                    try? engine.inputNode.setVoiceProcessingEnabled(false)
                }
                engine.reset()
            }
        }
        if echoMode == .automatic {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
            } catch {
                throw LiveError.audio("не удалось включить эхоподавление: \(error.localizedDescription)")
            }
        }

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw LiveError.audio("микрофон недоступен")
        }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw LiveError.audio("не удалось создать формат микрофона")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw LiveError.audio("не удалось создать конвертер микрофона")
        }
        if inputFormat.channelCount > 1 {
            converter.channelMap = [0]
        }
        guard let playFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        ) else {
            throw LiveError.audio("не удалось создать формат ответа")
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)

        let wiring = wireOutput(engine: engine, inputFormat: inputFormat, echoMode: echoMode)

        let box = LiveAudioConverter.Box(converter: converter, target: target)
        engine.inputNode
            .installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { @Sendable [weak self] buffer, _ in
                guard let converted = LiveAudioConverter.convert(buffer, box: box) else {
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self, self.running else {
                        return
                    }
                    if self.echoMode == .halfDuplex, !self.uplinkEnabled {
                        return
                    }
                    if !self.loggedFirstChunk {
                        self.loggedFirstChunk = true
                        Log.voice.notice("live audio: first mic chunk \(converted.data.count, privacy: .public) bytes")
                    }
                    self.onAudio?(converted.data)
                    self.onLevel?(converted.level)
                }
            }

        let rate = inputFormat.sampleRate
        let channels = inputFormat.channelCount
        let detail = "\(echoMode.rawValue) wiring=\(wiring) input=\(rate)Hz/\(channels)ch"
        Log.voice.notice("live audio: starting \(detail, privacy: .public)")
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.detach(player)
            Log.voice.error("live audio: start failed: \(error.localizedDescription, privacy: .public)")
            throw LiveError.audio("не удалось запустить аудио: \(error.localizedDescription)")
        }
        player.play()

        started = true
        self.engine = engine
        self.player = player
        self.playFormat = playFormat
        self.echoMode = echoMode
        self.loggedFirstChunk = false
        self.uplinkEnabled = true
        self.pendingBuffers = 0
        self.isPlaying = false
        self.running = true

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onError?(.audio("аудиоустройство изменилось"))
            }
        }

        Log.voice.notice("live audio: started, echo mode \(echoMode.rawValue, privacy: .public)")
    }

    public func stop() {
        guard running else {
            return
        }
        running = false
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        configurationObserver = nil
        player?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        if let engine, engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        player?.reset()
        if let player, let engine {
            engine.detach(player)
            engine.reset()
        }
        player = nil
        engine = nil
        playFormat = nil
        pendingBuffers = 0
        isPlaying = false
        Log.voice.notice("live audio: stopped")
    }

    /// Wires the mixer to the output. Voice processing requires both sides to share a clock,
    /// so the automatic mode uses the input sample rate.
    private func wireOutput(
        engine: AVAudioEngine,
        inputFormat: AVAudioFormat,
        echoMode: LiveEchoMode
    ) -> String {
        if echoMode == .automatic {
            let outChannels = engine.outputNode.inputFormat(forBus: 0).channelCount
            let outputFormat = AVAudioFormat(
                standardFormatWithSampleRate: inputFormat.sampleRate,
                channels: outChannels > 0 ? outChannels : 2
            ) ?? inputFormat
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
            return "input-rate"
        }
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        guard outputFormat.sampleRate > 0 else {
            return "automatic"
        }
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
        return "hardware"
    }
}

public extension LiveAudioIO {
    func setUplinkEnabled(_ enabled: Bool) {
        uplinkEnabled = enabled
    }

    func play(_ data: Data) {
        guard running, let player, let playFormat else {
            return
        }
        let frames = data.count / MemoryLayout<Int16>.size
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: playFormat,
                  frameCapacity: AVAudioFrameCount(frames)
              )
        else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        guard let channel = buffer.int16ChannelData?[0] else {
            return
        }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(channel, base, data.count)
            }
        }

        pendingBuffers += 1
        let wasPlaying = isPlaying
        isPlaying = true
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bufferFinished()
            }
        }
        if !wasPlaying {
            player.play()
            onPlaybackStarted?()
        }
    }

    func stopPlayback() {
        guard let player, isPlaying else {
            return
        }
        player.stop()
        pendingBuffers = 0
        isPlaying = false
        onPlaybackDrained?()
    }

    private func bufferFinished() {
        pendingBuffers = max(0, pendingBuffers - 1)
        guard pendingBuffers == 0, isPlaying else {
            return
        }
        isPlaying = false
        onPlaybackDrained?()
    }
}
