import Foundation
import GeraniaCore
@testable import RealtimeKit
import Testing

@Suite("Live protocol")
struct LiveProtocolTests {
    @Test("Setup carries the model, voice, transcription and tools")
    func setup() {
        let tool = LiveToolDeclaration(
            name: "run_task",
            description: "Starts a task",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "goal": .object(["type": .string("string")]),
                ]),
            ])
        )
        let configuration = LiveSessionConfiguration(
            apiKey: "key",
            model: "gemini-3.8-live",
            voiceName: "Kore",
            tools: [tool]
        )

        let frame = LiveWire.setup(configuration)
        let setup = frame["setup"]
        #expect(setup?["model"]?.stringValue == "models/gemini-3.8-live")
        #expect(setup?["generationConfig"]?["responseModalities"]?[0]?.stringValue == "AUDIO")
        let voice = setup?["generationConfig"]?["speechConfig"]?["voiceConfig"]?
            .objectValue?["prebuiltVoiceConfig"]?["voiceName"]?.stringValue
        #expect(voice == "Kore")
        #expect(setup?["inputAudioTranscription"] != nil)
        #expect(setup?["outputAudioTranscription"] != nil)
        #expect(setup?["contextWindowCompression"] != nil)
        #expect(setup?["sessionResumption"] != nil)
        #expect(setup?["tools"]?[0]?["functionDeclarations"]?[0]?["name"]?.stringValue == "run_task")
        #expect(
            setup?["tools"]?[0]?["functionDeclarations"]?[0]?["behavior"]?.stringValue
                == "NON_BLOCKING"
        )
    }

    @Test("Server content yields transcription, audio and turn events")
    func serverContent() {
        let frame: JSONValue = [
            "serverContent": [
                "inputTranscription": ["text": "привет"],
                "outputTranscription": ["text": "здравствуйте"],
                "modelTurn": [
                    "parts": [
                        [
                            "inlineData": [
                                "mimeType": "audio/pcm;rate=24000",
                                "data": "AAAA",
                            ],
                        ],
                    ],
                ],
                "interrupted": true,
                "turnComplete": true,
            ],
        ]

        let events = LiveWire.events(from: frame)
        #expect(events.contains(.inputTranscript("привет")))
        #expect(events.contains(.outputTranscript("здравствуйте")))
        #expect(events.contains(.audio(Data([0, 0, 0]), mimeType: "audio/pcm;rate=24000")))
        #expect(events.contains(.interrupted))
        #expect(events.contains(.turnComplete))
    }

    @Test("Tool calls keep ids, names and arguments")
    func toolCall() {
        let frame: JSONValue = [
            "toolCall": [
                "functionCalls": [
                    [
                        "id": "call-1",
                        "name": "run_task",
                        "args": ["goal": "открой Safari"],
                    ],
                ],
            ],
        ]

        let events = LiveWire.events(from: frame)
        guard case let .toolCall(calls)? = events.first else {
            Issue.record("expected a tool call")
            return
        }
        #expect(calls.count == 1)
        #expect(calls[0].id == "call-1")
        #expect(calls[0].name == "run_task")
        #expect(calls[0].arguments["goal"]?.stringValue == "открой Safari")
    }

    @Test("Resumption, go away and usage are decoded")
    func sessionEvents() {
        let resumption: JSONValue = [
            "sessionResumptionUpdate": [
                "newHandle": "handle-1",
                "resumable": true,
            ],
        ]
        #expect(LiveWire.events(from: resumption).contains(.resumptionUpdate(handle: "handle-1", resumable: true)))

        let goAway: JSONValue = ["goAway": ["timeLeft": "12s"]]
        #expect(LiveWire.events(from: goAway).contains(.goAway(12)))

        let usage: JSONValue = [
            "usageMetadata": [
                "promptTokenCount": 10,
                "responseTokenCount": 20,
                "totalTokenCount": 30,
            ],
        ]
        #expect(LiveWire.events(from: usage).contains(.usage(
            LiveUsage(promptTokens: 10, responseTokens: 20, totalTokens: 30)
        )))
    }

    @Test("Tool response uses the requested scheduling")
    func toolResponse() {
        let frame = LiveWire.toolResponse(
            callID: "call-1",
            name: "run_task",
            response: ["status": "done"],
            scheduling: .whenIdle
        )
        let responses = frame["toolResponse"]?["functionResponses"]
        #expect(responses?[0]?["id"]?.stringValue == "call-1")
        #expect(responses?[0]?["scheduling"]?.stringValue == "WHEN_IDLE")
        #expect(responses?[0]?["response"]?["status"]?.stringValue == "done")

        let noScheduling = LiveWire.toolResponse(
            callID: "call-2",
            name: "run_task",
            response: ["status": "done"],
            scheduling: nil
        )
        #expect(noScheduling["toolResponse"]?["functionResponses"]?[0]?["scheduling"] == nil)
    }
}
