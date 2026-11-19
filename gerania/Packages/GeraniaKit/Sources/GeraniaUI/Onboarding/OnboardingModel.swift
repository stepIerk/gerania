import Foundation
import GeraniaCore
import HermesKit
import Observation
import RealtimeKit
import VoiceKit

/// What a button of the wizard asks for.
enum SetupAction: Sendable, Equatable {
    case recheck
    case requestMicrophone
    case requestComputer
    case openPrivacy(String)
    case requestNotifications
    case startScheduler
    case openHermesDesktop
    case saveLiveKey(String)
    case speakTest
    case reminderTest
}

/// State of the first-run wizard.
///
/// The wizard is skippable at every step: a required step that fails only keeps
/// the warning on the last screen. Finishing writes one flag, so the wizard does
/// not reappear; «Мастер настройки…» in the menu opens it again.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var progress = SetupProgress()
    /// Result of the last button, shown under the status.
    public private(set) var actionMessage: String?
    public private(set) var isWorking = false

    @ObservationIgnored private let settings: GeraSettings
    @ObservationIgnored private let probes: SetupProbes
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored weak var appModel: AppModel?
    /// Closes the window and opens the main one.
    @ObservationIgnored var onFinish: (() -> Void)?

    static let completedKey = "onboardingCompleted"

    public static func isCompleted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey)
    }

    init(settings: GeraSettings, probes: SetupProbes? = nil, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        self.probes = probes ?? .live(SetupProbes.Context(
            config: Self.config(settings),
            pythonPath: settings.pythonPath,
            earsScriptOverridePath: settings.earsScriptOverridePath
        ))
    }

    func status(of step: SetupStep) -> SetupStatus {
        progress.status(of: step)
    }

    // MARK: - Navigation

    /// Quick checks for every step. The model is checked only on its own step:
    /// it sends a real prompt and may take half a minute.
    func checkAll() async {
        for step in SetupStep.allCases where step != .model && step != .tryIt {
            await check(step)
        }
    }

    func check(_ step: SetupStep) async {
        guard step != .tryIt else { return }
        progress.set(.checking, for: step)
        let result = await probes.run(step)
        progress.set(result, for: step)
    }

    func select(_ step: SetupStep) {
        actionMessage = nil
        progress.select(step)
        checkIfUnknown(step)
    }

    func next() {
        actionMessage = nil
        progress.advance()
        checkIfUnknown(progress.current)
    }

    func back() {
        actionMessage = nil
        progress.goBack()
    }

    func skip() {
        actionMessage = nil
        progress.skip(progress.current)
        checkIfUnknown(progress.current)
    }

    func finish() {
        defaults.set(true, forKey: Self.completedKey)
        Log.ui.info("onboarding finished, ready \(self.progress.readyCount, privacy: .public)")
        onFinish?()
    }

    private func checkIfUnknown(_ step: SetupStep) {
        guard progress.status(of: step) == .unknown else { return }
        Task { await self.check(step) }
    }

    // MARK: - Actions

    func perform(_ action: SetupAction) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        actionMessage = await run(action)
        await check(progress.current)
    }

    private func run(_ action: SetupAction) async -> String? {
        let config = Self.config(settings)
        switch action {
        case .recheck:
            return nil
        case .requestMicrophone:
            let granted = await MicrophoneAccess.request()
            return granted ? nil : "macOS не дал доступ. Включите Gerania в настройках микрофона."
        case .requestComputer:
            return await ComputerUseInspector(config: config).requestPermissions()
        case let .openPrivacy(service):
            SystemSettingsLink.openPrivacy(service)
            return "Включите переключатель и вернитесь — нажмите «Проверить»."
        case .requestNotifications:
            let access = await CronNotifier.requestIfNeeded()
            if access == .denied {
                CronNotifier.openSystemSettings()
            }
            return nil
        case .startScheduler:
            do {
                try await CronJobsStore(config: config).ensureGateway()
                try? await Task.sleep(for: .seconds(2))
                return "Gateway запущен. Первый тик планировщика — в течение минуты."
            } catch {
                return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        case .openHermesDesktop:
            let opened = await DesktopLauncher().openApplication()
            return opened
                ? "Hermes Desktop открыт. Выберите провайдера, вставьте ключ и вернитесь сюда."
                : "Hermes Desktop не установлен. Установите его — он поставит и агента."
        case let .saveLiveKey(key):
            return saveLiveKey(key)
        case .speakTest:
            appModel?.speakNow("Привет! Я Гера. Скажите «Гера» — и я вас услышу.")
            return "Если голоса не слышно, проверьте громкость и вкладку «Голос»."
        case .reminderTest:
            return await createTestReminder(config: config)
        }
    }

    private func saveLiveKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Вставьте ключ Gemini API." }
        do {
            try LiveCredentials.saveAPIKey(trimmed)
            settings.liveVoiceEnabled = true
            return "Ключ сохранён в Связке ключей, живой диалог включён."
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func createTestReminder(config: HermesConfig) async -> String {
        let request = CronJobRequest(
            name: "Проверка напоминаний Геры",
            schedule: "in 1m",
            prompt: "Ответь одной короткой фразой по-русски: напоминания Геры работают.",
            timezone: TimeZone.current.identifier
        )
        do {
            try await CronJobsStore(config: config).create(request)
            return "Готово: через 1–2 минуты придёт уведомление «Проверка напоминаний Геры»."
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    static func config(_ settings: GeraSettings) -> HermesConfig {
        HermesConfig(
            hermesPath: settings.hermesPath,
            provider: settings.provider,
            model: settings.model,
            workdir: settings.workdir,
            voicePromptPrefix: "",
            textPromptPrefix: ""
        )
    }
}
