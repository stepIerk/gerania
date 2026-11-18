import Foundation
import GeraniaCore
import GeraniaUI
import Testing

/// Records what the orchestrator asks the window layer to do.
@MainActor
private final class FakePanels: PanelPresenting {
    var presented: [GeraState] = []
    var updates: [GeraState] = []
    var dismissed: [TimeInterval] = []
    var inputShown = false

    func presentHUD(state: GeraState) {
        presented.append(state)
    }

    func updateHUD(state: GeraState) {
        updates.append(state)
    }

    func dismissHUD(after delay: TimeInterval) {
        dismissed.append(delay)
    }

    func presentInput(prefill: String, showChats: Bool) {
        inputShown = true
    }
}

@Suite("AppModel и панели")
@MainActor
struct AppModelPanelTests {
    private func model() -> (AppModel, FakePanels) {
        let defaults = UserDefaults(suiteName: "GeraniaUITests-\(UUID().uuidString)") ?? .standard
        let model = AppModel(settings: GeraSettings(defaults: defaults))
        let panels = FakePanels()
        model.panels = panels
        return (model, panels)
    }

    @Test("Wake shows the HUD panel")
    func wakeShowsPanel() {
        let (model, panels) = model()

        model.dispatch(.wake(at: 100))

        #expect(panels.presented.count == 1)
        if case .listening = panels.presented.first {
            // ok
        } else {
            Issue.record("expected the listening state to be presented")
        }
    }

    @Test("Open input shows the input panel")
    func openInputShowsPanel() {
        let (model, panels) = model()

        model.openInput()

        #expect(panels.inputShown)
    }

    @Test("Completion hides the panel after the delay")
    func completionHidesPanel() {
        let (model, panels) = model()

        model.dispatch(.wake(at: 100))
        model.dispatch(.promptSubmitted)
        model.dispatch(.completed(finalText: "готово"))

        #expect(panels.dismissed.contains(6))
    }

    @Test("Debug route shows the HUD panel")
    func debugRouteShowsPanel() throws {
        let (model, panels) = model()
        let url = try #require(URL(string: "gerania://debug/state?name=streaming"))

        model.handle(url: url)

        #expect(panels.presented.count == 1)
        #expect(panels.updates.last == .streaming)
    }
}
