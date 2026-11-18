import GeraniaUI
import SwiftUI

@main
struct GeraniaApp: App {
    @NSApplicationDelegateAdaptor(GeraniaAppDelegate.self) private var appDelegate

    private var model: AppModel {
        GeraniaAppRoot.shared.model
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model, onOpenWindow: openMainWindow)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel(model.menuBarLabel)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Настройки…") {
                    openMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// The window of the application: the welcome screen and the settings.
    private func openMainWindow() {
        GeraniaAppRoot.shared.mainWindow.show()
    }
}
