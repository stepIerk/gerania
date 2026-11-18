import Foundation

/// A server→client request from Hermes (approval, clarify, …).
public struct ServerRequest: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case approval
        case clarify
        case other(String)
    }

    public let id: String
    public let kind: Kind
    public let sessionID: String?
    public let command: String?
    public let requestDescription: String?
    public let choices: [String]
    public let executionGeneration: Int?
    public let admissionID: String?

    public init(
        id: String,
        kind: Kind,
        sessionID: String? = nil,
        command: String? = nil,
        requestDescription: String? = nil,
        choices: [String] = [],
        executionGeneration: Int? = nil,
        admissionID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sessionID = sessionID
        self.command = command
        self.requestDescription = requestDescription
        self.choices = choices
        self.executionGeneration = executionGeneration
        self.admissionID = admissionID
    }
}

public enum ServerRequestAnswer: Sendable, Equatable {
    case approval(choice: String)
    case clarify(answer: String)
    case cancel
}
