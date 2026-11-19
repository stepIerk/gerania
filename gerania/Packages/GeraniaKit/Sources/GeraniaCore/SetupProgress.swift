import Foundation

/// One step of the first-run wizard, in the order it is shown.
public enum SetupStep: String, CaseIterable, Sendable, Identifiable {
    case hermes
    case model
    case liveKey
    case microphone
    case computer
    case notifications
    case scheduler
    case tryIt

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .hermes: "Hermes"
        case .model: "Модель"
        case .liveKey: "Живой диалог"
        case .microphone: "Микрофон и голос"
        case .computer: "Управление компьютером"
        case .notifications: "Уведомления"
        case .scheduler: "Планировщик"
        case .tryIt: "Проверка"
        }
    }

    public var symbol: String {
        switch self {
        case .hermes: "shippingbox"
        case .model: "cpu"
        case .liveKey: "waveform.circle"
        case .microphone: "mic"
        case .computer: "cursorarrow.click.2"
        case .notifications: "bell"
        case .scheduler: "clock"
        case .tryIt: "checkmark.seal"
        }
    }

    /// Why the step matters, one or two sentences for the wizard.
    public var explanation: String {
        switch self {
        case .hermes:
            "Hermes — агент, который выполняет задачи Геры: пишет код, ищет, работает с файлами. "
                + "Без него Гера не отвечает."
        case .model:
            "Модель, которой думает Hermes. Ключ провайдера хранится в Hermes; Гера проверяет, "
                + "что модель отвечает."
        case .liveKey:
            "Живой диалог Gemini — основной голосовой режим: Гера слушает и отвечает без пауз, "
                + "а работу на компьютере передаёт Hermes. Ключ хранится в Связке ключей."
        case .microphone:
            "Микрофон нужен, чтобы Гера услышала «Гера». Распознавание идёт на этом Mac."
        case .computer:
            "Чтобы кликать и видеть экран, драйвер CuaDriver просит «Универсальный доступ» и "
                + "«Запись экрана». Без них Гера работает, но не управляет компьютером."
        case .notifications:
            "Уведомления сообщают о готовых напоминаниях и задачах, даже когда окно закрыто."
        case .scheduler:
            "Планировщик Hermes запускает напоминания и утренние брифинги по расписанию."
        case .tryIt:
            "Последний шаг: услышать Геру и поставить тестовое напоминание на минуту."
        }
    }

    /// A required step blocks Gera; the others only switch features off.
    public var isRequired: Bool {
        self == .hermes || self == .model
    }
}

/// Result of checking one step.
public enum SetupStatus: Sendable, Equatable {
    case unknown
    case checking
    case ok(String)
    case warning(String)
    case failed(String)
    case skipped

    /// The person can move on from this step.
    public var isSettled: Bool {
        switch self {
        case .ok, .warning, .skipped: true
        case .unknown, .checking, .failed: false
        }
    }

    public var message: String? {
        switch self {
        case let .ok(text), let .warning(text), let .failed(text): text
        case .skipped: "Пропущено — можно вернуться позже из меню «Мастер настройки…»."
        case .checking: "Проверяю…"
        case .unknown: nil
        }
    }
}

/// Where the wizard is: the current step and the result of every check.
public struct SetupProgress: Sendable, Equatable {
    public private(set) var current: SetupStep
    private var statuses: [SetupStep: SetupStatus] = [:]

    public init(current: SetupStep = .hermes) {
        self.current = current
    }

    public func status(of step: SetupStep) -> SetupStatus {
        statuses[step] ?? .unknown
    }

    public mutating func set(_ status: SetupStatus, for step: SetupStep) {
        statuses[step] = status
    }

    public mutating func skip(_ step: SetupStep) {
        statuses[step] = .skipped
        if step == current {
            advance()
        }
    }

    public mutating func select(_ step: SetupStep) {
        current = step
    }

    /// Moves to the next step; stays on the last one.
    public mutating func advance() {
        guard let index = SetupStep.allCases.firstIndex(of: current),
              index + 1 < SetupStep.allCases.count
        else {
            return
        }
        current = SetupStep.allCases[index + 1]
    }

    public mutating func goBack() {
        guard let index = SetupStep.allCases.firstIndex(of: current), index > 0 else { return }
        current = SetupStep.allCases[index - 1]
    }

    public var isLastStep: Bool {
        current == SetupStep.allCases.last
    }

    /// Required steps that still fail: Gera will not answer until they are fixed.
    public var blockers: [SetupStep] {
        SetupStep.allCases.filter { step in
            guard step.isRequired else { return false }
            if case .failed = status(of: step) {
                return true
            }
            return false
        }
    }

    /// Steps checked as fine, for the «3 из 8» counter.
    public var readyCount: Int {
        SetupStep.allCases.filter { step in
            if case .ok = status(of: step) {
                return true
            }
            return false
        }.count
    }
}
