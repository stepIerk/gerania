import Foundation

/// Applies panel size changes outside the SwiftUI layout pass.
///
/// Geometry changes are reported from inside the window's layout pass. Moving the
/// window frame right there starts another constraint pass; AppKit throws
/// "The window has been marked as needing another Update Constraints in Window
/// pass" after its guard limit. The scheduler coalesces a burst of reports and
/// applies only the last value on the next main-queue turn, when the pass is over.
@MainActor
final class PanelResizeScheduler {
    private var pending: (value: CGFloat, apply: @MainActor (CGFloat) -> Void)?
    private var isScheduled = false

    /// Remembers the latest size and applies it after the current run-loop turn.
    func submit(_ value: CGFloat, apply: @escaping @MainActor (CGFloat) -> Void) {
        pending = (value, apply)
        guard !isScheduled else { return }
        isScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.isScheduled = false
            guard let pending = self.pending else { return }
            self.pending = nil
            pending.apply(pending.value)
        }
    }
}
