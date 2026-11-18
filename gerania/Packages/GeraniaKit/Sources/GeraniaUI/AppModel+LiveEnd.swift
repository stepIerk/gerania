import Foundation
import GeraniaCore

/// Soft completion of the live dialog: a farewell must not cut Gera off.
extension AppModel {
    /// The user or the model said goodbye: close the dialog after Gera finishes
    /// speaking, not in the middle of the farewell.
    func requestLiveEnd(reason: String) {
        guard isLiveActive, liveConversation != nil, liveEndPending == nil else {
            return
        }
        liveEndPending = reason
        Log.voice.notice("live: end requested: \(reason, privacy: .public)")
        // A last-resort guard: a stuck turn must not keep the microphone forever.
        liveEndWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.liveEndPending != nil else { return }
            // Clear the handle before closing: `commitLiveEnd` must not cancel
            // the task it is running in.
            self.liveEndWatchdog = nil
            await self.commitLiveEnd()
        }
        maybeCommitLiveEnd()
    }

    /// The dialog continues: forget the pending goodbye.
    func cancelLiveEnd() {
        guard liveEndPending != nil else {
            return
        }
        Log.voice.notice("live: end cancelled")
        liveEndPending = nil
        liveEndWatchdog?.cancel()
        liveEndWatchdog = nil
        liveEndCommit?.cancel()
        liveEndCommit = nil
        liveTurnFinished = false
    }

    /// Closes the dialog when the turn is complete and the playback is drained.
    func maybeCommitLiveEnd() {
        guard liveEndPending != nil, liveTurnFinished, !liveSpeaking, liveEndCommit == nil else {
            return
        }
        // `turnComplete` can arrive before the first audio chunk of the goodbye.
        liveEndCommit = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else {
                return
            }
            self.liveEndCommit = nil
            guard self.liveEndPending != nil, self.liveTurnFinished, !self.liveSpeaking else {
                return
            }
            await self.commitLiveEnd()
        }
    }

    private func commitLiveEnd() async {
        guard let reason = liveEndPending else {
            return
        }
        liveEndPending = nil
        // Do not cancel this task from inside itself: `finishLive` clears the rest.
        liveEndCommit = nil
        liveEndWatchdog?.cancel()
        liveEndWatchdog = nil
        liveTurnFinished = false
        await finishLive(reason: reason)
    }
}
