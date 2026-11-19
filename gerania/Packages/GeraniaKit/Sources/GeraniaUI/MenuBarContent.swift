import AppKit
import GeraniaCore
import HermesKit
import SwiftUI

/// Items shown by `MenuBarExtra`.
public struct MenuBarContent: View {
    private let model: AppModel
    private let onOpenWindow: () -> Void

    public init(model: AppModel, onOpenWindow: @escaping () -> Void) {
        self.model = model
        self.onOpenWindow = onOpenWindow
    }

    public var body: some View {
        if NetworkStatus.shared.isOffline {
            Text("Нет интернета — облачные модели недоступны")
            Divider()
        }
        Button("Спросить…") {
            model.openInput()
        }
        recentChats
        Button("Новый чат") {
            model.newChat()
        }
        Divider()
        Button(model.settings.voiceEnabled ? "Микрофон: включён" : "Микрофон: выключен") {
            Task { await model.setVoiceEnabled(!model.settings.voiceEnabled) }
        }
        Divider()
        Button("Окно Гера…") {
            onOpenWindow()
        }
        Button("Мастер настройки…") {
            GeraniaAppRoot.shared.onboarding.show()
        }
        Divider()
        Button("Выход") {
            NSApp.terminate(nil)
        }
    }

    /// The eight most recent chats; the current one is marked.
    private var recentChats: some View {
        Menu("Недавние чаты") {
            if model.chats.sessions.isEmpty {
                Text("Пока нет чатов")
            } else {
                ForEach(Array(model.chats.sessions.prefix(8)), id: \.id) { session in
                    Button {
                        model.chats.select(sessionID: session.id)
                    } label: {
                        Text(label(for: session))
                    }
                }
            }
        }
    }

    private func label(for session: SessionSummary) -> String {
        let title = session.title.isEmpty ? session.id : session.title
        let marker = session.id == model.chats.currentSessionID ? "• " : ""
        return marker + title
    }
}
