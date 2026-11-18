import Foundation

/// Settings of one live conversation.
public struct LiveConversationConfiguration: Sendable {
    public var session: LiveSessionConfiguration
    public var echoMode: LiveEchoMode
    public var idleTimeout: TimeInterval
    public var maxDuration: TimeInterval

    public init(
        session: LiveSessionConfiguration,
        echoMode: LiveEchoMode = .automatic,
        idleTimeout: TimeInterval = 60,
        maxDuration: TimeInterval = 1800
    ) {
        self.session = session
        self.echoMode = echoMode
        self.idleTimeout = idleTimeout
        self.maxDuration = maxDuration
    }
}
