import Foundation
import GeraniaCore

public struct LiveToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct LiveUsage: Sendable, Equatable {
    public let promptTokens: Int
    public let responseTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, responseTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.responseTokens = responseTokens
        self.totalTokens = totalTokens
    }
}

public enum LiveEvent: Sendable, Equatable {
    case setupComplete
    case inputTranscript(String)
    case outputTranscript(String)
    case audio(Data, mimeType: String)
    case interrupted
    case turnComplete
    case toolCall([LiveToolCall])
    case toolCallCancellation([String])
    case resumptionUpdate(handle: String, resumable: Bool)
    case goAway(TimeInterval?)
    case usage(LiveUsage)
    case closed(reason: String?)
    case error(LiveError)
}
