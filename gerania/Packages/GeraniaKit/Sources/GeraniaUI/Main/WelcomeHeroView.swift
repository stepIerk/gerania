import AppKit
import SwiftUI
import VoiceKit

/// Приветственный блок окна: иконка, состояние Геры и кнопка запуска.
struct WelcomeHeroView: View {
    private let model: AppModel
    private let onLaunch: () -> Void
    private let onStop: () -> Void

    init(model: AppModel, onLaunch: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.model = model
        self.onLaunch = onLaunch
        self.onStop = onStop
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Гера")
                    .font(.system(size: 20, weight: .semibold))
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                }
            }
            Spacer(minLength: 12)
            button
        }
        .padding(20)
    }

    @ViewBuilder
    private var button: some View {
        if model.isVoiceRunning {
            Button("Остановить", action: onStop)
                .controlSize(.large)
        } else {
            Button(action: onLaunch) {
                Label("Запустить Геранию", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var status: String {
        if model.isVoiceRunning {
            return "Голос работает — Геря слушает «Гера»"
        }
        return "Голос выключен — нажмите кнопку, чтобы Геря заработала"
    }

    /// Подсказка, если Герю не удалось запустить.
    private var hint: String? {
        guard !model.isVoiceRunning else { return nil }
        if let error = model.launchError {
            return error
        }
        return MicrophoneAccess.isDenied
            ? "Нет доступа к микрофону — разрешите его в Системных настройках"
            : nil
    }
}
