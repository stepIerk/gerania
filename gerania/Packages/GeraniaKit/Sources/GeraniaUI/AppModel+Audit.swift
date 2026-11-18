import Foundation
import GeraniaCore
import HermesKit

/// Writes the actions of a turn to the journal.
///
/// The journal is best-effort: a missing directory, a full disk or a broken
/// file must never break the answer. The actor is fire-and-forget from the turn.
extension AppModel {
    /// Records a finished tool with its short argument and result.
    func recordToolAudit(_ chip: ToolChip, ok: Bool) {
        let entry = AuditEntry(
            tool: chip.name,
            detail: AuditLog.redacted(chip.detail),
            decision: chip.isComputerUse ? "computer" : "auto",
            ok: ok,
            summary: AuditLog.redacted(chip.summary)
        )
        let log = auditLog
        Task { await log.append(entry) }
    }

    /// Records how the person answered an approval or a clarification.
    func recordAnswerAudit(_ request: ServerRequest, answer: ServerRequestAnswer) {
        let decision = switch answer {
        case let .approval(choice): choice
        case .clarify: "answered"
        case .cancel: "cancelled"
        }
        let entry = AuditEntry(
            tool: request.kind == .approval ? "approval" : "clarify",
            detail: AuditLog.redacted(request.command ?? request.requestDescription),
            decision: decision,
            ok: answer != .cancel
        )
        let log = auditLog
        Task { await log.append(entry) }
    }
}
