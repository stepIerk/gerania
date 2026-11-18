import Foundation
import GeraniaCore

public enum LiveToolScheduling: String, Sendable, Equatable {
    case whenIdle = "WHEN_IDLE"
    case silent = "SILENT"
    case interrupt = "INTERRUPT"
}

enum LiveWire {
    static func setup(_ configuration: LiveSessionConfiguration) -> JSONValue {
        var setup: [String: JSONValue] = [
            "model": .string(modelName(configuration.model)),
            "generationConfig": .object([
                "responseModalities": .array([.string("AUDIO")]),
                "speechConfig": .object([
                    "voiceConfig": .object([
                        "prebuiltVoiceConfig": .object([
                            "voiceName": .string(configuration.voiceName),
                        ]),
                    ]),
                ]),
            ]),
            "systemInstruction": .object([
                "parts": .array([
                    .object(["text": .string(configuration.systemInstruction)]),
                ]),
            ]),
            "realtimeInputConfig": .object([
                "automaticActivityDetection": .object([
                    "startOfSpeechSensitivity": .string(configuration.vad.startSensitivity.rawValue),
                    "endOfSpeechSensitivity": .string(configuration.vad.endSensitivity.rawValue),
                    "prefixPaddingMs": .int(Int64(configuration.vad.prefixPaddingMs)),
                    "silenceDurationMs": .int(Int64(configuration.vad.silenceDurationMs)),
                ]),
            ]),
        ]

        if configuration.inputTranscription {
            setup["inputAudioTranscription"] = .object([:])
        }
        if configuration.outputTranscription {
            setup["outputAudioTranscription"] = .object([:])
        }
        if configuration.contextWindowCompression {
            setup["contextWindowCompression"] = .object([
                "slidingWindow": .object([:]),
            ])
        }
        if configuration.sessionResumption {
            setup["sessionResumption"] = .object([:])
        }
        if !configuration.tools.isEmpty {
            setup["tools"] = .array([
                .object([
                    "functionDeclarations": .array(configuration.tools.map(declaration)),
                ]),
            ])
        }

        return .object(["setup": .object(setup)])
    }

    static func audio(_ data: Data) -> JSONValue {
        .object([
            "realtimeInput": .object([
                "audio": .object([
                    "data": .string(data.base64EncodedString()),
                    "mimeType": .string("audio/pcm;rate=16000"),
                ]),
            ]),
        ])
    }

    static func text(_ text: String) -> JSONValue {
        .object([
            "clientContent": .object([
                "turns": .array([
                    .object([
                        "role": .string("user"),
                        "parts": .array([
                            .object(["text": .string(text)]),
                        ]),
                    ]),
                ]),
                "turnComplete": .bool(true),
            ]),
        ])
    }

    static func toolResponse(
        callID: String,
        name: String,
        response: JSONValue,
        scheduling: LiveToolScheduling?
    ) -> JSONValue {
        var entry: [String: JSONValue] = [
            "id": .string(callID),
            "name": .string(name),
            "response": response,
        ]
        if let scheduling {
            entry["scheduling"] = .string(scheduling.rawValue)
        }
        return .object([
            "toolResponse": .object([
                "functionResponses": .array([.object(entry)]),
            ]),
        ])
    }

    static func events(from frame: JSONValue) -> [LiveEvent] {
        var events: [LiveEvent] = []

        if frame["setupComplete"] != nil {
            events.append(.setupComplete)
        }

        if let server = frame["serverContent"] {
            if let text = server["inputTranscription"]?["text"]?.stringValue, !text.isEmpty {
                events.append(.inputTranscript(text))
            }
            let transcription = server["outputTranscription"]?["text"]?.stringValue ?? ""
            if !transcription.isEmpty {
                events.append(.outputTranscript(transcription))
            }
            if let turn = server["modelTurn"] {
                for part in turn["parts"]?.arrayValue ?? [] {
                    if part["thought"]?.boolValue == true {
                        continue
                    }
                    if let inline = part["inlineData"],
                       let encoded = inline["data"]?.stringValue,
                       let audio = Data(base64Encoded: encoded)
                    {
                        let mime = inline["mimeType"]?.stringValue ?? "audio/pcm;rate=24000"
                        events.append(.audio(audio, mimeType: mime))
                    } else if let text = part["text"]?.stringValue,
                              !text.isEmpty,
                              transcription.isEmpty
                    {
                        events.append(.outputTranscript(text))
                    }
                }
            }
            if server["interrupted"]?.boolValue == true {
                events.append(.interrupted)
            }
            if server["turnComplete"]?.boolValue == true {
                events.append(.turnComplete)
            }
        }

        if let toolCall = frame["toolCall"] {
            let calls = (toolCall["functionCalls"]?.arrayValue ?? []).compactMap { row -> LiveToolCall? in
                guard let id = row["id"]?.stringValue,
                      let name = row["name"]?.stringValue
                else { return nil }
                return LiveToolCall(id: id, name: name, arguments: row["args"] ?? .object([:]))
            }
            if !calls.isEmpty {
                events.append(.toolCall(calls))
            }
        }

        if let cancellation = frame["toolCallCancellation"] {
            let ids = (cancellation["ids"]?.arrayValue ?? []).compactMap(\.stringValue)
            if !ids.isEmpty {
                events.append(.toolCallCancellation(ids))
            }
        }

        if let update = frame["sessionResumptionUpdate"] {
            let handle = update["newHandle"]?.stringValue ?? ""
            let resumable = update["resumable"]?.boolValue ?? false
            events.append(.resumptionUpdate(handle: handle, resumable: resumable))
        }

        if let goAway = frame["goAway"] {
            events.append(.goAway(seconds(goAway["timeLeft"])))
        }

        if let usage = frame["usageMetadata"] {
            events.append(.usage(LiveUsage(
                promptTokens: usage["promptTokenCount"]?.intValue ?? 0,
                responseTokens: usage["responseTokenCount"]?.intValue ?? 0,
                totalTokens: usage["totalTokenCount"]?.intValue ?? 0
            )))
        }

        if let error = frame["error"] {
            let message = error["message"]?.stringValue ?? "unknown error"
            events.append(.error(LiveError(serverMessage: message)))
        }

        return events
    }

    private static func declaration(_ tool: LiveToolDeclaration) -> JSONValue {
        .object([
            "name": .string(tool.name),
            "description": .string(tool.description),
            "parameters": tool.parameters,
            "behavior": .string(tool.behavior.rawValue),
        ])
    }

    private static func modelName(_ model: String) -> String {
        model.hasPrefix("models/") ? model : "models/\(model)"
    }

    private static func seconds(_ value: JSONValue?) -> TimeInterval? {
        if let number = value?.doubleValue {
            return number
        }
        guard let text = value?.stringValue else {
            return nil
        }
        let trimmed = text.hasSuffix("s") ? String(text.dropLast()) : text
        return TimeInterval(trimmed)
    }
}
