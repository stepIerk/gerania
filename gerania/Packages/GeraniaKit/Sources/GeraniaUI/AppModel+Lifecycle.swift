import Foundation
import GeraniaCore

/// What quitting would interrupt. Closing the window never interrupts anything:
/// Gera stays in the menu bar. Only ⌘Q ends the process.
extension AppModel {
    /// A sentence for the quit confirmation, `nil` when nothing is running.
    var busyReasonForQuit: String? {
        let tasks = liveTaskManager?.snapshots.filter { !$0.status.isTerminal }.count ?? 0
        if tasks > 0 {
            return "Фоновых задач в работе: \(tasks)."
        }
        if hud.isComputerUseActive {
            return "Гера сейчас управляет компьютером."
        }
        switch state {
        case .thinking, .streaming, .awaitingApproval:
            return "Гера отвечает на запрос."
        default:
            return nil
        }
    }
}
