import AppKit
import GeraniaCore
import SwiftUI
import UniformTypeIdentifiers

/// «Голос» → microphone: when Gera listens, how hard she filters noise and
/// what catches «Гера».
struct VoiceInputSection: View {
    let model: AppModel

    private var input: VoiceInputController {
        model.voiceInput
    }

    var body: some View {
        Section("Когда слушать") {
            Picker("Режим", selection: listenMode) {
                ForEach(ListenMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            note(input.settings.listenMode.detail)
        }
        Section("Слово «Гера» и шум") {
            statusRow(
                ok: input.usesNeuralVAD,
                title: input.usesNeuralVAD ? "Речь отличает нейросеть Silero" : "Речь отличает спектральный фильтр",
                detail: "\(input.speechDetail). «Гера»: \(input.wakeDetail)."
            )
            Picker("Защита от шума", selection: noiseRejection) {
                ForEach(NoiseRejection.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            note(input.settings.noiseRejection.detail)
        }
        Section("Своя модель wake-слова") {
            LabeledContent("Модуль") {
                Text(pluginName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Button("Выбрать модуль…") {
                    pickPlugin()
                }
                if !input.settings.wakePluginPath.isEmpty {
                    Button("Убрать — снова Whisper") {
                        setPlugin("")
                    }
                }
            }
            note(
                "Python-модуль с функцией create(environ), например обёртка над openWakeWord. "
                    + "Пока его нет, «Гера» распознаёт Whisper. Формат — в docs/VOICE_IPC.md."
            )
        }
    }

    // MARK: - Pieces

    private var pluginName: String {
        let path = input.settings.wakePluginPath
        return path.isEmpty ? "не выбран" : (path as NSString).lastPathComponent
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(ok ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pickPlugin() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "py") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setPlugin(url.path)
    }

    private func setPlugin(_ path: String) {
        input.settings.wakePluginPath = path
        Task { await model.restartEars() }
    }

    // MARK: - Bindings

    private var listenMode: Binding<ListenMode> {
        Binding(
            get: { input.settings.listenMode },
            set: { mode in
                input.settings.listenMode = mode
                Task { await model.sendVoiceInputSettings() }
            }
        )
    }

    private var noiseRejection: Binding<NoiseRejection> {
        Binding(
            get: { input.settings.noiseRejection },
            set: { level in
                input.settings.noiseRejection = level
                Task { await model.sendVoiceInputSettings() }
            }
        )
    }
}
