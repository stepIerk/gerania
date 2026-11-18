import Foundation
import GeraniaCore
import HermesKit

/// Finished plans: a system banner and a HUD card.
public extension AppModel {
    /// How many banners one batch may post; the rest is one summary banner.
    internal static let cronBannerLimit = 3

    /// Announces results the monitor found. Several results at once happen
    /// after a launch, when plans ran while Gerania was closed.
    func announceCronResults(_ results: [CronResult]) {
        guard let latest = results.last else { return }
        if settings.notifications {
            let shown = results.suffix(Self.cronBannerLimit)
            for result in shown {
                let title = result.digest.isFailure
                    ? "План «\(result.title)» не выполнился"
                    : "Гера: \(result.title)"
                let body = result.digest.body.isEmpty ? "Результат готов." : result.digest.body
                let identifier = result.id
                let file = result.output.url
                Task {
                    await CronNotifier.post(identifier: identifier, title: title, body: body, file: file)
                }
            }
            let hidden = results.count - shown.count
            if hidden > 0 {
                Task {
                    await CronNotifier.post(
                        identifier: "gerania.cron.summary.\(latest.id)",
                        title: "Ещё \(hidden) результатов планов",
                        body: "Они во вкладке «Планы» окна Геры.",
                        file: nil
                    )
                }
            }
        }
        showCronCard(latest, others: results.count - 1)
    }

    /// The card appears only when Gera is not busy: a reminder must not cut
    /// into an answer or the microphone. The banner covers the busy case.
    internal func showCronCard(_ result: CronResult, others: Int) {
        switch state {
        case .idle, .done, .error:
            break
        default:
            Log.ui.info("cron card skipped: Gera is busy")
            return
        }
        hud.reset()
        hud.heardText = nil
        hud.appendDelta(Self.cronCardText(result, others: others))
        hud.flushStream()
        apply(state: .done)
        panels?.presentHUD(state: .done)
        panels?.dismissHUD(after: adjustedHideDelay(10))
    }

    /// Markdown of the HUD card.
    internal static func cronCardText(_ result: CronResult, others: Int) -> String {
        let heading = result.digest.isFailure
            ? "**⚠️ План «\(result.title)» не выполнился**"
            : "**⏰ \(result.title)**"
        var lines = [heading]
        if !result.digest.body.isEmpty {
            lines.append(result.digest.body)
        }
        if others > 0 {
            lines.append("_Ещё результатов: \(others) — во вкладке «Планы»._")
        }
        return lines.joined(separator: "\n\n")
    }
}
