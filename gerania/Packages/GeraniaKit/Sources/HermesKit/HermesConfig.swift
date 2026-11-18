import Foundation
import GeraniaCore

public struct HermesConfig: Sendable, Equatable {
    public var hermesPath: String
    public var provider: String
    public var model: String
    public var workdir: String
    public var voicePromptPrefix: String
    public var textPromptPrefix: String
    public var homeDirectory: String
    public var sessionTitlePrefix: String
    public var gatewayTimeout: Int

    public init(
        hermesPath: String = "",
        provider: String = "gemini",
        model: String = "gemini-2.5-flash-lite",
        workdir: String = "~/AgentWork",
        voicePromptPrefix: String? = nil,
        textPromptPrefix: String = "",
        homeDirectory: String = NSHomeDirectory(),
        sessionTitlePrefix: String = "gerania",
        gatewayTimeout: Int = 60
    ) {
        self.hermesPath = hermesPath
        self.provider = provider
        self.model = model
        self.workdir = workdir
        self.voicePromptPrefix = voicePromptPrefix
            ?? GeraSettings.defaultVoicePromptPrefix(workdir: (workdir as NSString).expandingTildeInPath)
        self.textPromptPrefix = textPromptPrefix
        self.homeDirectory = homeDirectory
        self.sessionTitlePrefix = sessionTitlePrefix
        self.gatewayTimeout = gatewayTimeout
    }

    public var expandedWorkdir: String {
        (workdir as NSString).expandingTildeInPath
    }

    public var stateDatabaseURL: URL {
        URL(fileURLWithPath: homeDirectory).appendingPathComponent(".hermes/state.db")
    }

    public func prompt(for text: String, mode: PromptMode) -> String {
        switch mode {
        case .voice:
            voicePromptPrefix + text
        case .text:
            textPromptPrefix + text
        }
    }

    public func hermesBinary() throws -> URL {
        let locator = BinaryLocator.live(homeDirectory: homeDirectory)
        guard let url = locator.locateHermes(configuredPath: hermesPath) else {
            throw HermesError.binaryNotFound
        }
        return url
    }

    public func processEnvironment() -> [String: String] {
        BinaryLocator.live(homeDirectory: homeDirectory).environment()
    }
}
