import Foundation
import GeraniaCore
import Testing

@Suite("Настройки")
@MainActor
struct GeraSettingsTests {
    @Test("Старая позиция панели один раз переезжает под чёлку")
    func panelPositionMigration() {
        let defaults = UserDefaults(suiteName: "GeraniaSettingsTests-\(UUID().uuidString)") ?? .standard
        defaults.set(PanelPosition.topRight.rawValue, forKey: "panelPosition")

        let settings = GeraSettings(defaults: defaults)
        #expect(settings.panelPosition == .notch)

        settings.panelPosition = .topRight
        let reopened = GeraSettings(defaults: defaults)
        #expect(reopened.panelPosition == .topRight)
    }

    @Test("Показ модели в HUD включается и сохраняется")
    func showActiveModel() {
        let defaults = UserDefaults(suiteName: "GeraniaSettingsTests-\(UUID().uuidString)") ?? .standard
        let settings = GeraSettings(defaults: defaults)
        #expect(settings.showActiveModelInHUD)

        settings.showActiveModelInHUD = false
        let reopened = GeraSettings(defaults: defaults)
        #expect(reopened.showActiveModelInHUD == false)
    }
}
