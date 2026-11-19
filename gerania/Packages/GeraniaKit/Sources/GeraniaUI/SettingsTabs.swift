import GeraniaCore
import HermesKit
import KeyboardShortcuts
import RealtimeKit
import SwiftUI
import VoiceKit

/// Вкладки настроек приложения.
///
/// Одни и те же вкладки живут в окне приложения и вызываются из меню-бара,
/// поэтому настройки везде показывают одно и то же состояние.
public struct SettingsTabs: View {
    @Bindable private var settings: GeraSettings
    private let chatsModel: ChatsModel
    private let auditLog: AuditLog
    private let memory: MemoryModel
    @State private var liveKey = ""
    @State private var liveKeyStatus: String?

    public init(
        settings: GeraSettings,
        chats: ChatsModel? = nil,
        auditLog: AuditLog? = nil,
        memory: MemoryModel
    ) {
        self.settings = settings
        chatsModel = chats ?? ChatsModel(settings: settings)
        self.auditLog = auditLog ?? AuditLog()
        self.memory = memory
    }

    public var body: some View {
        TabView {
            general
                .tabItem { Text("Основные") }
            hermes
                .tabItem { Text("Hermes") }
            voice
                .tabItem { Text("Голос") }
            MemoryTab(model: memory)
                .tabItem { Text("Память") }
            PlansTab(settings: settings)
                .tabItem { Text("Планы") }
            chats
                .tabItem { Text("Чаты") }
            audit
                .tabItem { Text("Журнал") }
            diagnostics
                .tabItem { Text("Диагностика") }
        }
    }

    private var audit: some View {
        Form {
            AuditSection(log: auditLog)
        }
        .formStyle(.grouped)
    }

    private var general: some View {
        Form {
            Picker("Терминал для сессий", selection: $settings.terminalApp) {
                ForEach(TerminalPreference.allCases, id: \.self) { app in
                    Text(app.displayName).tag(app)
                }
            }
            Toggle("Вводить ID сессии в Desktop (экспериментально)", isOn: $settings.experimentalDesktopKeys)
            Picker("Положение панели", selection: $settings.panelPosition) {
                ForEach(PanelPosition.allCases) { position in
                    Text(position.displayName).tag(position)
                }
            }
            HStack {
                Text("Ширина окна ответа")
                Slider(value: $settings.detailPanelWidth, in: 400 ... 720, step: 10)
                Text("\(Int(settings.detailPanelWidth)) pt")
                    .monospacedDigit()
            }
            HStack {
                Text("Отступ окна ответа")
                Slider(value: $settings.detailPanelMargin, in: 0 ... 48, step: 2)
                Text("\(Int(settings.detailPanelMargin)) pt")
                    .monospacedDigit()
            }
            Divider()
            ShortcutRow("Открыть мини-окно", name: .openInput)
            ShortcutRow("Говорить (нажать или удерживать)", name: .pushToTalk)
            ShortcutRow("Остановить ответ", name: .stopAll)
            ShortcutRow("Микрофон вкл/выкл", name: .toggleMicrophone)
            HStack {
                Text("Скрывать через")
                Slider(value: $settings.autoHideSeconds, in: 2 ... 30, step: 1)
                Text("\(Int(settings.autoHideSeconds)) с")
                    .monospacedDigit()
            }
            HStack {
                Text("Максимальная высота")
                Slider(value: $settings.maxPanelHeightFraction, in: 0.3 ... 0.9)
                Text(settings.maxPanelHeightFraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            Toggle("Автозапуск при входе", isOn: $settings.launchAtLogin)
            Toggle("Уведомления", isOn: $settings.notifications)
        }
        .formStyle(.grouped)
    }

    private var hermes: some View {
        Form {
            TextField("Путь к hermes", text: $settings.hermesPath, prompt: Text("/opt/homebrew/bin/hermes"))
            Picker("Транспорт", selection: $settings.transport) {
                ForEach(TransportKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            TextField("Провайдер", text: $settings.provider, prompt: Text("gemini"))
            ModelCandidatesSection(settings: settings)
            ComputerUseSection(settings: settings)
            TextField("Рабочая папка", text: $settings.workdir, prompt: Text("~/AgentWork"))
            Toggle("Продолжать последнюю сессию", isOn: $settings.continueLastSession)
            TextField("Python для голоса", text: $settings.pythonPath, prompt: Text("venv/bin/python"))
            TextField("Префикс текстового режима", text: $settings.textPromptPrefix, axis: .vertical)
        }
        .formStyle(.grouped)
    }

    private var voice: some View {
        Form {
            Toggle("Голосовой режим", isOn: $settings.voiceEnabled)
            VoiceInputSection(model: GeraniaAppRoot.shared.model)
            liveDialog
            Toggle("Озвучивать ответы", isOn: $settings.speakAnswers)
            TextField("Голос", text: $settings.voiceName)
            HStack {
                Text("Скорость речи")
                Slider(value: $settings.speechRate, in: 0.3 ... 0.8)
            }
            TextField("Максимум символов для озвучки", value: $settings.maxSpokenChars, format: .number)
            Picker("Подтверждения", selection: $settings.approvalPolicy) {
                ForEach(ApprovalPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            TextField("Префикс голосового запроса", text: $settings.voicePromptPrefix, axis: .vertical)
            TextField("Скрипт «ушей» (override)", text: $settings.earsScriptOverridePath)
            microphone
        }
        .formStyle(.grouped)
    }

    /// Живой диалог: после wake микрофон забирает Gemini Live.
    private var liveDialog: some View {
        GroupBox("Живой диалог Gemini") {
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Включить живой диалог", isOn: $settings.liveVoiceEnabled)
                Text("Wake-слово по-прежнему ловит Whisper. Gemini подключается только после «Гера».")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                HStack {
                    SecureField("Ключ Gemini API", text: $liveKey)
                    Button("Сохранить") { saveLiveKey() }
                    Button("Удалить") { deleteLiveKey() }
                }
                LabeledContent(
                    "Ключ",
                    value: LiveCredentials.isConfigured ? "задан" : "не задан"
                )
                Picker("Модель", selection: $settings.liveModel) {
                    ForEach(LiveModelCatalog.entries) { entry in
                        Text(entry.title).tag(entry.id)
                    }
                    if !LiveModelCatalog.entries.contains(where: { $0.id == settings.liveModel }) {
                        Text(settings.liveModel).tag(settings.liveModel)
                    }
                }
                Text(liveModelNote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                TextField("Голос", text: $settings.liveVoiceName, prompt: Text("Kore"))
                HStack {
                    Text("Закрывать после тишины")
                    Slider(value: $settings.liveIdleSeconds, in: 20 ... 180, step: 5)
                    Text("\(Int(settings.liveIdleSeconds)) с")
                        .monospacedDigit()
                }
                if let liveKeyStatus {
                    Text(liveKeyStatus)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var liveModelNote: String {
        let note = LiveModelCatalog.entries.first { $0.id == settings.liveModel }?.note ?? "Своя модель"
        return "\(note). Если у модели кончится лимит, Гера сама перейдёт на следующую из списка."
    }

    private func saveLiveKey() {
        do {
            try LiveCredentials.saveAPIKey(liveKey)
            liveKey = ""
            liveKeyStatus = "Ключ сохранён в Keychain"
        } catch {
            liveKeyStatus = error.localizedDescription
        }
    }

    private func deleteLiveKey() {
        do {
            try LiveCredentials.deleteAPIKey()
            liveKey = ""
            liveKeyStatus = "Ключ удалён"
        } catch {
            liveKeyStatus = error.localizedDescription
        }
    }

    /// Пороги распознавания: если речь режется, их нужно ослабить.
    private var microphone: some View {
        GroupBox("Микрофон") {
            VStack(alignment: .leading, spacing: 6) {
                slider("Чувствительность", value: $settings.micMinRMS, range: 0.001 ... 0.02)
                slider("Порог шума ×", value: $settings.micNoiseMultiplier, range: 1 ... 6)
                slider("Доля голоса в спектре", value: $settings.micBandRatioMin, range: 0.01 ... 0.2)
                slider("Терпимость к шуму", value: $settings.micFlatnessMax, range: 0.2 ... 0.9)
                slider("Кадров голоса", value: $settings.micMinTonalFraction, range: 0.05 ... 0.6)
                Text("Изменения применяются к «ушам» при следующем запуске голоса.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(3)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var chats: some View {
        ChatsSettingsView(chats: chatsModel)
    }

    private var diagnostics: some View {
        DiagnosticsTab(settings: settings)
    }
}
