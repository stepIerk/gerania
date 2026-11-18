import Foundation

/// One tool invocation shown inside the thinking HUD state.
public struct ToolChip: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let detail: String?
    public let isFinished: Bool
    public let isError: Bool
    /// Local screenshot the tool produced, shown in the answer window.
    public let imagePath: String?
    /// Short result of the call: a page title, a count of pages, a URL host.
    public let summary: String?

    public init(
        id: String,
        name: String,
        detail: String? = nil,
        isFinished: Bool = false,
        isError: Bool = false,
        imagePath: String? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.isFinished = isFinished
        self.isError = isError
        self.imagePath = imagePath
        self.summary = summary
    }

    public func finished(ok: Bool) -> ToolChip {
        ToolChip(
            id: id,
            name: name,
            detail: detail,
            isFinished: true,
            isError: !ok,
            imagePath: imagePath,
            summary: summary
        )
    }

    /// Whether this call drives the Mac through `computer_use`.
    public var isComputerUse: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("computer_use")
    }

    /// Attaches what the tool returned, keeping the call itself intact.
    public func withOutput(imagePath: String?, summary: String?) -> ToolChip {
        ToolChip(
            id: id,
            name: name,
            detail: detail,
            isFinished: isFinished,
            isError: isError,
            imagePath: imagePath ?? self.imagePath,
            summary: summary ?? self.summary
        )
    }
}
