import Foundation
import GeraniaCore

public enum LiveEchoMode: String, Sendable, Equatable, CaseIterable {
    case automatic
    case halfDuplex

    public var displayName: String {
        switch self {
        case .automatic:
            "Эхоподавление"
        case .halfDuplex:
            "Полудуплекс"
        }
    }
}

public enum LiveVADStartSensitivity: String, Sendable, Equatable {
    case low = "START_SENSITIVITY_LOW"
    case high = "START_SENSITIVITY_HIGH"
}

public enum LiveVADEndSensitivity: String, Sendable, Equatable {
    case low = "END_SENSITIVITY_LOW"
    case high = "END_SENSITIVITY_HIGH"
}

public struct LiveVADConfiguration: Sendable, Equatable {
    public var startSensitivity: LiveVADStartSensitivity
    public var endSensitivity: LiveVADEndSensitivity
    public var prefixPaddingMs: Int
    public var silenceDurationMs: Int

    public init(
        startSensitivity: LiveVADStartSensitivity = .high,
        endSensitivity: LiveVADEndSensitivity = .high,
        prefixPaddingMs: Int = 200,
        silenceDurationMs: Int = 500
    ) {
        self.startSensitivity = startSensitivity
        self.endSensitivity = endSensitivity
        self.prefixPaddingMs = prefixPaddingMs
        self.silenceDurationMs = silenceDurationMs
    }
}

public enum LiveToolBehavior: String, Sendable, Equatable {
    case blocking = "BLOCKING"
    case nonBlocking = "NON_BLOCKING"
}

public struct LiveToolDeclaration: Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: JSONValue
    public let behavior: LiveToolBehavior

    public init(
        name: String,
        description: String,
        parameters: JSONValue,
        behavior: LiveToolBehavior = .nonBlocking
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.behavior = behavior
    }
}

public struct LiveSessionConfiguration: Sendable, Equatable {
    public var apiKey: String
    public var model: String
    public var voiceName: String
    public var systemInstruction: String
    public var tools: [LiveToolDeclaration]
    public var inputTranscription: Bool
    public var outputTranscription: Bool
    public var contextWindowCompression: Bool
    public var sessionResumption: Bool
    public var vad: LiveVADConfiguration
    public var endpoint: String
    public var setupTimeout: TimeInterval

    public init(
        apiKey: String,
        model: String = "gemini-3.8-live",
        voiceName: String = "Kore",
        systemInstruction: String = LivePrompt.defaultInstruction,
        tools: [LiveToolDeclaration] = [],
        inputTranscription: Bool = true,
        outputTranscription: Bool = true,
        contextWindowCompression: Bool = true,
        sessionResumption: Bool = true,
        vad: LiveVADConfiguration = LiveVADConfiguration(),
        endpoint: String = "wss://generativelanguage.googleapis.com/ws/"
            + "google.ai.generativelanguage.v1beta."
            + "GenerativeService.BidiGenerateContent",
        setupTimeout: TimeInterval = 15
    ) {
        self.apiKey = apiKey
        self.model = model
        self.voiceName = voiceName
        self.systemInstruction = systemInstruction
        self.tools = tools
        self.inputTranscription = inputTranscription
        self.outputTranscription = outputTranscription
        self.contextWindowCompression = contextWindowCompression
        self.sessionResumption = sessionResumption
        self.vad = vad
        self.endpoint = endpoint
        self.setupTimeout = setupTimeout
    }
}
