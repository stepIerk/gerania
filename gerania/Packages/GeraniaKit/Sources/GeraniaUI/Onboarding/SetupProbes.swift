import Foundation
import GeraniaCore
import HermesKit
import RealtimeKit
import VoiceKit

/// The checks behind every wizard step.
///
/// Each probe only reads state (files, Keychain, TCC, one test prompt for the
/// model) and never changes Hermes settings. The struct is a seam: the tests
/// pass fakes and never touch the real system.
struct SetupProbes: Sendable {
    var run: @Sendable (SetupStep) async -> SetupStatus

    /// What the probes need from the settings, copied so they are `Sendable`.
    struct Context: Sendable {
        var config: HermesConfig
        var pythonPath: String
        var earsScriptOverridePath: String
    }

    static func live(_ context: Context) -> SetupProbes {
        SetupProbes { step in
            Log.ui.info("setup check: \(step.rawValue, privacy: .public)")
            switch step {
            case .hermes:
                return Self.hermes(context.config)
            case .model:
                return await Self.model(context.config)
            case .liveKey:
                return Self.liveKey()
            case .microphone:
                return Self.microphone(context)
            case .computer:
                return await Self.computer(context.config)
            case .notifications:
                return await Self.notifications()
            case .scheduler:
                return Self.scheduler()
            case .tryIt:
                return .unknown
            }
        }
    }

    // MARK: - Checks

    static func hermes(_ config: HermesConfig) -> SetupStatus {
        do {
            let binary = try config.hermesBinary()
            return .ok("Hermes найден: \((binary.path as NSString).abbreviatingWithTildeInPath)")
        } catch {
            return .failed(
                "Hermes не найден. Установите Hermes Desktop (он ставит и агента), откройте его один раз "
                    + "и нажмите «Проверить». Если Hermes стоит в другом месте, укажите путь на вкладке «Hermes»."
            )
        }
    }

    static func model(_ config: HermesConfig) async -> SetupStatus {
        if config.provider.isEmpty || config.model.isEmpty {
            return .warning("Модель не выбрана в Гере: Hermes ответит своей моделью по умолчанию.")
        }
        let credentials = ProviderCredentials.status(
            provider: config.provider,
            homeDirectory: config.homeDirectory
        )
        if let missing = credentials.missingLabel {
            return .failed(
                "Нет ключа \(missing) для «\(config.provider)». Добавьте его в Hermes Desktop "
                    + "(настройки провайдера) и нажмите «Проверить»."
            )
        }
        let candidate = ModelCandidate(provider: config.provider, model: config.model)
        let result = await ModelProbe(config: config).check(candidate, timeout: 45)
        return result.isSuccess
            ? .ok("\(candidate.displayName) отвечает: «\(result.detail)»")
            : .failed("\(candidate.displayName) не ответила: \(result.detail)")
    }

    static func liveKey() -> SetupStatus {
        LiveCredentials.isConfigured
            ? .ok("Ключ Gemini сохранён в Связке ключей.")
            : .warning("Ключа нет: Гера будет слушать через Whisper и отвечать через Hermes, без живого диалога.")
    }

    static func microphone(_ context: Context) -> SetupStatus {
        if MicrophoneAccess.isDenied {
            return .failed(
                "Микрофон запрещён. Системные настройки → Конфиденциальность и безопасность → "
                    + "Микрофон → включите Gerania."
            )
        }
        let script = VoicePaths.script(override: context.earsScriptOverridePath, scriptDirectory: nil)
        let python = VoicePaths.python(
            configured: context.pythonPath,
            scriptDirectory: VoicePaths.scriptDirectory(scriptPath: script)
        )
        if python == nil {
            return .failed(
                "Не найдено окружение распознавания речи (voice-venv). Его ставит "
                    + "scripts/setup_voice.sh, подробности — в README, раздел «Голос»."
            )
        }
        return MicrophoneAccess.isAuthorized
            ? .ok("Микрофон разрешён, распознавание установлено.")
            : .warning("Микрофон ещё не спрашивали: нажмите «Разрешить микрофон».")
    }

    static func computer(_ config: HermesConfig) async -> SetupStatus {
        let status = await ComputerUseInspector(config: config).inspect()
        if status.isReady {
            return .ok("CuaDriver готов: есть «Универсальный доступ» и «Запись экрана».")
        }
        return .warning("\(status.summary). Без этого Гера отвечает и пишет код, но не кликает.")
    }

    static func notifications() async -> SetupStatus {
        switch await CronNotifier.access() {
        case .allowed: .ok("Уведомления разрешены.")
        case .notDetermined: .warning("Уведомления ещё не разрешены: нажмите «Разрешить уведомления».")
        case .denied: .warning(NotificationAccess.denied.text)
        case .unknown: .warning(NotificationAccess.unknown.text)
        }
    }

    static func scheduler() -> SetupStatus {
        let status = CronSchedulerStatus.read(cronDirectory: CronJobsStore.defaultDirectory())
        return status.isRunning ? .ok(status.title) : .warning("\(status.title). \(status.detail)")
    }
}
