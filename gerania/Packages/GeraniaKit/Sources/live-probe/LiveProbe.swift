import Darwin
import Foundation
import GeraniaCore
import RealtimeKit

@main
struct LiveProbe {
    @MainActor
    static func main() async {
        let options = Options(arguments: Array(CommandLine.arguments.dropFirst()))
        guard !options.seconds.isNaN, options.seconds > 0 else {
            log("--seconds must be positive")
            exit(2)
        }
        if options.audioOnly {
            await runAudioOnly(options)
            return
        }
        guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty else {
            log("GEMINI_API_KEY is not set")
            exit(2)
        }

        let configuration = LiveSessionConfiguration(
            apiKey: key,
            model: options.model,
            voiceName: options.voice,
            systemInstruction: LivePrompt.defaultInstruction,
            inputTranscription: true,
            outputTranscription: true,
            contextWindowCompression: true,
            sessionResumption: true,
            vad: LiveVADConfiguration(),
            setupTimeout: 20
        )
        let transport = GeminiLiveTransport(configuration: configuration)
        let events = await transport.events()
        let audio = LiveAudioIO()

        audio.onAudio = { data in
            Task {
                await transport.sendAudio(data)
            }
        }
        audio.onLevel = { level in
            Task { @MainActor in
                _ = level
            }
        }
        audio.onPlaybackStarted = {
            Task { @MainActor in
                log("speaking…")
            }
        }
        audio.onPlaybackDrained = {
            Task { @MainActor in
                log("ready")
            }
        }
        audio.onError = { error in
            Task { @MainActor in
                log("audio error: \(error.localizedDescription)")
            }
        }

        if !options.noMicrophone {
            do {
                try audio.start(
                    echoMode: options.halfDuplex ? .halfDuplex : .automatic
                )
            } catch {
                log("microphone error: \(error.localizedDescription)")
                exit(1)
            }
        }

        let consumer = Task { @MainActor in
            await consume(events, audio: audio, transport: transport)
        }

        do {
            try await transport.connect()
        } catch {
            log("connect failed: \(error.localizedDescription)")
            audio.stop()
            consumer.cancel()
            exit(1)
        }

        if let text = options.text {
            do {
                try await transport.sendText(text)
                log("sent text: \(text)")
            } catch {
                log("send text failed: \(error.localizedDescription)")
            }
        }

        log("running for \(options.seconds) s")
        try? await Task.sleep(for: .seconds(options.seconds))
        await transport.close(reason: "probe finished")
        audio.stop()
        consumer.cancel()
    }

    @MainActor
    private static func runAudioOnly(_ options: Options) async {
        let audio = LiveAudioIO()
        audio.onLevel = { level in
            Task { @MainActor in
                _ = level
            }
        }
        audio.onError = { error in
            Task { @MainActor in
                log("audio error: \(error.localizedDescription)")
            }
        }
        do {
            let mode = try await audio.startWithFallback(
                echoMode: options.halfDuplex ? .halfDuplex : .automatic
            )
            log("audio started: \(mode.rawValue)")
        } catch {
            log("microphone error: \(error.localizedDescription)")
            exit(1)
        }
        try? await Task.sleep(for: .seconds(options.seconds))
        audio.stop()
        log("audio stopped")
    }

    @MainActor
    private static func consume(
        _ events: AsyncStream<LiveEvent>,
        audio: LiveAudioIO,
        transport: GeminiLiveTransport
    ) async {
        for await event in events {
            switch event {
            case .setupComplete:
                log("setup complete")
            case let .inputTranscript(text):
                log("you: \(text)")
            case let .outputTranscript(text):
                log("gera: \(text)")
            case let .audio(data, _):
                audio.play(data)
            case .interrupted:
                audio.stopPlayback()
                log("interrupted")
            case .turnComplete:
                log("turn complete")
            case let .toolCall(calls):
                for call in calls {
                    log("tool call: \(call.name) \(call.arguments)")
                    let response: JSONValue = ["error": "live-probe does not run tools"]
                    try? await transport.sendToolResponse(
                        callID: call.id,
                        name: call.name,
                        response: response,
                        scheduling: .whenIdle
                    )
                }
            case let .toolCallCancellation(ids):
                log("tool call cancelled: \(ids.joined(separator: ", "))")
            case let .resumptionUpdate(handle, resumable):
                log("resumption: \(handle.isEmpty ? "none" : "updated") resumable=\(resumable)")
            case let .goAway(seconds):
                log("go away in \(seconds ?? -1) s")
            case let .usage(usage):
                log("usage: prompt=\(usage.promptTokens) "
                    + "response=\(usage.responseTokens) total=\(usage.totalTokens)")
            case let .closed(reason):
                log("closed: \(reason ?? "no reason")")
            case let .error(error):
                log("error: \(error.localizedDescription)")
            }
        }
    }

    private static func log(_ text: String) {
        guard let data = (text + "\n").data(using: .utf8) else {
            return
        }
        FileHandle.standardOutput.write(data)
    }
}

private struct Options {
    var text: String?
    var seconds: Double = 45
    var model = "gemini-3.8-live"
    var voice = "Kore"
    var noMicrophone = false
    var halfDuplex = false
    var audioOnly = false

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--text":
                text = value(after: &index, in: arguments)
            case "--seconds":
                seconds = value(after: &index, in: arguments).flatMap(Double.init) ?? seconds
            case "--model":
                model = value(after: &index, in: arguments) ?? model
            case "--voice":
                voice = value(after: &index, in: arguments) ?? voice
            case "--no-mic":
                noMicrophone = true
            case "--half-duplex":
                halfDuplex = true
            case "--audio-only":
                audioOnly = true
            default:
                break
            }
            index += 1
        }
    }

    private func value(after index: inout Int, in arguments: [String]) -> String? {
        let next = index + 1
        guard next < arguments.count else {
            return nil
        }
        index = next
        return arguments[next]
    }
}
