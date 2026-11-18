import Foundation

/// Every event that can move `GeraState`.
public enum GeraAction: Sendable, Equatable {
    case wake(at: TimeInterval)
    case listenTimedOut
    case transcriptionStarted
    case transcriptionFailed(String)
    case promptSubmitted
    case turnStarted
    case textStarted
    case textDelta(String)
    case reasoningDelta(String)
    case toolStarted(ToolChip)
    case toolOutput(id: String, imagePath: String?, summary: String?)
    case toolFinished(id: String, ok: Bool)
    case serverRequest(ServerRequest)
    case serverRequestAnswered
    case completed(finalText: String?)
    case cancelled
    case speechStarted
    case speechFinished
    case stop
    case failed(String)
    case dismissed
}
