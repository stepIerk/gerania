import Foundation
import GeraniaCore

/// Watchdog for `computer_use`.
///
/// While Gerania drives the Mac the HUD shows an amber frame and a stop button.
/// After ten minutes of continuous control it says so: unattended clicking is
/// worth a reminder, and the person may have walked away.
extension AppModel {
    /// Ten minutes of continuous control before the reminder.
    static let computerUseReminderDelay: TimeInterval = 10 * 60

    /// The menu bar shows the screen while the Mac is under control: the state
    /// of Gerania itself matters less than the fact that clicks are happening.
    public var menuBarSymbol: String {
        if hud.isComputerUseActive {
            return "display"
        }
        return switch state {
        case .idle, .done: "waveform"
        case .listening: "mic.fill"
        case .transcribing: "waveform.badge.mic"
        case .thinking: "ellipsis.bubble"
        case .streaming: "text.bubble"
        case .speaking: "speaker.wave.2"
        case .error: "exclamationmark.triangle"
        case .awaitingApproval: "hand.raised"
        }
    }

    public var menuBarLabel: String {
        hud.isComputerUseActive ? "Гера управляет компьютером" : "Гера — \(state.displayName)"
    }

    /// Starts the reminder when the first `computer_use` call begins.
    func startComputerUseWatch(delay: TimeInterval = AppModel.computerUseReminderDelay) {
        guard computerUseTask == nil else { return }
        hud.computerUseNotice = nil
        computerUseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.computerUseTask = nil
            guard self.hud.isComputerUseActive else { return }
            self.hud.computerUseNotice = "Управляю компьютером уже 10 минут"
            if self.shouldSpeak {
                self.speakNow(
                    "Гера управляет компьютером уже десять минут. Скажите «стоп», чтобы остановить."
                )
            }
            Log.ui.info("computer use reminder shown")
        }
    }

    /// Cancels the reminder when the computer is no longer under control.
    func stopComputerUseWatch() {
        computerUseTask?.cancel()
        computerUseTask = nil
        hud.computerUseNotice = nil
    }
}
