import Foundation
import GeraniaCore

/// One live conversation: Gemini Live, the microphone and the speaker.
///
/// The class owns the audio and the WebSocket, forwards the protocol events to the
/// application and ends the session after a silence or the time limit.
@MainActor
public final class LiveConversation {
    public var onEvent: ((LiveEvent) -> Void)?
    public var onLevel: ((Double) -> Void)?
    public var onSpeakingChanged: ((Bool) -> Void)?

    public let configuration: LiveConversationConfiguration

    private let transport: GeminiLiveTransport
    private let audio = LiveAudioIO()
    private var eventTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var startedAt = Date()
    private var lastActivity = Date()
    private var closedReported = false
    private var isSending = false
    private var loggedFirstAudio = false
    private var loggedFirstInput = false
    private var loggedFirstOutput = false

    public init(configuration: LiveConversationConfiguration) {
        self.configuration = configuration
        transport = GeminiLiveTransport(configuration: configuration.session)
    }

    /// Whether the setup is complete and the session is alive.
    public private(set) var isActive = false

    /// Whether the transport is connected and ready to listen.
    public private(set) var isPrepared = false

    /// Connects to Gemini without opening the microphone.
    ///
    /// The ears keep the microphone while the user finishes the first phrase:
    /// the connection happens in parallel, so no word is lost and the handoff
    /// takes milliseconds.
    public func prepare() async throws {
        guard !isPrepared, !isActive else {
            return
        }
        closedReported = false
        loggedFirstAudio = false
        loggedFirstInput = false
        loggedFirstOutput = false
        let events = await transport.events()
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
        installAudio()

        Log.voice.notice("live: connecting")
        do {
            try await transport.connect()
        } catch {
            eventTask?.cancel()
            eventTask = nil
            throw error
        }

        guard !closedReported, await transport.isConnected else {
            eventTask?.cancel()
            eventTask = nil
            throw LiveError.sessionClosed("сессия закрылась при подключении")
        }
        isPrepared = true
        Log.voice.notice("live: connected, waiting for the first phrase")
    }

    /// Opens the microphone after the first phrase is fully recognized.
    public func startListening() async throws {
        guard !isActive else {
            return
        }
        guard isPrepared else {
            throw LiveError.sessionClosed("сессия не готова")
        }
        do {
            try await startAudio()
        } catch {
            eventTask?.cancel()
            eventTask = nil
            await transport.close(reason: error.localizedDescription)
            throw error
        }

        isActive = true
        startedAt = Date()
        lastActivity = startedAt
        startWatchdog()
        Log.voice.notice("live: listening")
    }

    /// Connects, starts the audio and sends the command from the wake phrase.
    public func start(seed: String? = nil) async throws {
        try await prepare()
        try await startListening()

        if let seed {
            let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try await transport.sendText(trimmed)
            }
        }
        Log.voice.notice("live: conversation started")
    }

    /// Sends a text turn to the model.
    public func sendText(_ text: String) async throws {
        guard isActive else {
            throw LiveError.sessionClosed("сессия не готова")
        }
        try await transport.sendText(text)
        touch()
    }

    /// Sends the result of a tool call.
    public func sendToolResponse(
        callID: String,
        name: String,
        response: JSONValue,
        scheduling: LiveToolScheduling? = .whenIdle
    ) async throws {
        guard isActive else {
            throw LiveError.sessionClosed("сессия не готова")
        }
        try await transport.sendToolResponse(
            callID: callID,
            name: name,
            response: response,
            scheduling: scheduling
        )
        touch()
    }

    /// Closes the session. The microphone is released before Python gets it back.
    ///
    /// The `.closed` event still comes through `onEvent`.
    public func close(reason: String? = nil) async {
        if isSending || closedReported {
            return
        }
        isSending = true
        isActive = false
        isPrepared = false
        watchdogTask?.cancel()
        watchdogTask = nil
        audio.stop()
        onSpeakingChanged?(false)
        defer { isSending = false }
        await transport.close(reason: reason)
    }

    private func startAudio() async throws {
        let mode = try await audio.startWithFallback(echoMode: configuration.echoMode)
        Log.voice.notice("live: audio ready \(mode.rawValue, privacy: .public)")
    }

    /// Keeps the current turn from the idle timer.
    public func noteActivity() {
        touch()
    }

    private func installAudio() {
        audio.onAudio = { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.transport.sendAudio(data)
            }
        }
        audio.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.onLevel?(level)
            }
        }
        audio.onPlaybackStarted = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handlePlaybackStarted()
            }
        }
        audio.onPlaybackDrained = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handlePlaybackDrained()
            }
        }
        audio.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.onEvent?(.error(error))
            }
        }
    }

    private func handle(_ event: LiveEvent) {
        switch event {
        case .audio:
            touch()
        case .inputTranscript:
            touch()
            if !loggedFirstInput {
                loggedFirstInput = true
                Log.voice.notice("live: first input transcript")
            }
        case .outputTranscript:
            touch()
            if !loggedFirstOutput {
                loggedFirstOutput = true
                Log.voice.notice("live: first output transcript")
            }
        case .turnComplete:
            touch()
        case .interrupted:
            audio.stopPlayback()
            touch()
        case .closed:
            closedReported = true
            stopInternals()
        case .error:
            break
        default:
            break
        }

        if case let .audio(data, _) = event {
            if !loggedFirstAudio {
                loggedFirstAudio = true
                Log.voice.notice("live: first audio chunk received")
            }
            audio.play(data)
        }

        onEvent?(event)
    }

    private func handlePlaybackStarted() {
        audio.setUplinkEnabled(false)
        onSpeakingChanged?(true)
        touch()
    }

    private func handlePlaybackDrained() {
        audio.setUplinkEnabled(true)
        onSpeakingChanged?(false)
        touch()
    }

    private func touch() {
        lastActivity = Date()
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.isActive else { return }
                let now = Date()
                if now.timeIntervalSince(self.startedAt) >= self.configuration.maxDuration {
                    await self.close(reason: "лимит сессии")
                    return
                }
                if now.timeIntervalSince(self.lastActivity) >= self.configuration.idleTimeout {
                    await self.close(reason: "тишина")
                    return
                }
            }
        }
    }

    private func stopInternals() {
        isActive = false
        isPrepared = false
        watchdogTask?.cancel()
        watchdogTask = nil
        audio.stop()
        onSpeakingChanged?(false)
        eventTask?.cancel()
        eventTask = nil
        Log.voice.notice("live: conversation stopped")
    }
}
