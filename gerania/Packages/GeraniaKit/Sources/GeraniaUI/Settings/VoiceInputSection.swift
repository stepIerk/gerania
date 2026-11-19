import AppKit
import GeraniaCore
import SwiftUI
import UniformTypeIdentifiers
import VoiceKit

/// «Голос» → microphone: when Gera listens, the «Гера» detector and the owner voice.
struct VoiceInputSection: View {
    let model: AppModel

    @State private var accessKey = ""
    @State private var message: String?
    @State private var status = WakeEngine.status()

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
            Text(input.settings.listenMode.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section("Слово «Гера»") {
            engineRow(
                active: input.keywordActive,
                title: input.keywordActive ? "Детектор Porcupine работает" : "Запасной режим: Whisper",
                detail: input.keywordActive
                    ? "«Гера» ловится мгновенно, Whisper включается только после неё."
                    : "Причина: \(input.keywordDetail). Без детектора Гера просыпается медленнее."
            )
            HStack {
                SecureField(keyPrompt, text: $accessKey)
                Button("Сохранить") {
                    let key = accessKey
                    accessKey = ""
                    Task {
                        message = await model.saveWakeKey(key)
                        refresh()
                    }
                }
                .disabled(accessKey.isEmpty)
            }
            HStack {
                fileButton("Файл слова (.ppn)…", ready: status.hasKeyword, destination: WakeEngine.keywordURL())
                fileButton("Русская модель (.pv)…", ready: status.hasModel, destination: WakeEngine.modelURL())
            }
            LabeledContent("Чувствительность") {
                Slider(value: sensitivity, in: 0.3 ... 0.9, step: 0.05) { editing in
                    if !editing {
                        Task { await model.restartEars() }
                    }
                }
                .frame(width: 180)
            }
            Text("Ключ и файл слова создаются бесплатно в Picovoice Console — инструкция в HUMAN_TODO §13.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        ownerSection
        if let message {
            Text(message)
                .font(.system(size: 11))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var ownerSection: some View {
        Section("Только мой голос") {
            engineRow(
                active: input.ownerActive,
                title: input.ownerActive ? "Голос владельца проверяется" : "Проверка голоса выключена",
                detail: input.ownerActive
                    ? "Чужие голоса, телевизор и речь самой Геры не будят её и не дают команд."
                    : "Причина: \(input.ownerDetail)."
            )
            Toggle("Слушать только мой голос", isOn: ownerGate)
                .disabled(!status.hasOwnerProfile)
            if let percent = input.enrollPercent {
                ProgressView(value: percent, total: 100) {
                    Text(input.enrollMessage ?? "Запись…")
                        .font(.system(size: 11))
                }
                Button("Отменить запись") {
                    model.cancelOwnerVoiceRecording()
                }
            } else {
                HStack {
                    Button(status.hasOwnerProfile ? "Перезаписать мой голос" : "Записать мой голос") {
                        Task {
                            await model.recordOwnerVoice()
                            refresh()
                        }
                    }
                    .disabled(!status.hasKey)
                    if status.hasOwnerProfile {
                        Button("Удалить запись") {
                            Task {
                                await model.forgetOwnerVoice()
                                refresh()
                            }
                        }
                    }
                }
                if let note = input.enrollMessage {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Строгость") {
                Slider(value: threshold, in: 0.3 ... 0.8, step: 0.05) { editing in
                    if !editing {
                        Task { await model.restartEars() }
                    }
                }
                .frame(width: 180)
            }
        }
    }

    // MARK: - Pieces

    private func engineRow(active: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: active ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(active ? Color.green : Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fileButton(_ title: String, ready: Bool, destination: URL) -> some View {
        Button {
            pick(into: destination)
        } label: {
            Label(title, systemImage: ready ? "checkmark.circle.fill" : "doc.badge.plus")
        }
    }

    private func pick(into destination: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: destination.pathExtension) ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            message = await model.installWakeFile(from: url, as: destination)
            refresh()
        }
    }

    private var keyPrompt: String {
        status.hasKey ? "Ключ Picovoice сохранён" : "Ключ Picovoice (AccessKey)"
    }

    private func refresh() {
        status = WakeEngine.status()
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

    private var ownerGate: Binding<Bool> {
        Binding(
            get: { input.settings.ownerGateEnabled },
            set: { enabled in
                input.settings.ownerGateEnabled = enabled
                Task { await model.sendVoiceInputSettings() }
            }
        )
    }

    private var sensitivity: Binding<Double> {
        Binding(
            get: { input.settings.keywordSensitivity },
            set: { input.settings.keywordSensitivity = $0 }
        )
    }

    private var threshold: Binding<Double> {
        Binding(
            get: { input.settings.ownerThreshold },
            set: { input.settings.ownerThreshold = $0 }
        )
    }
}
