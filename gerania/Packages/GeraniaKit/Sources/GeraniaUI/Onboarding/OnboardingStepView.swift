import GeraniaCore
import SwiftUI

/// The right side of the wizard: what the step is, its status and what to do.
struct OnboardingStepView: View {
    let model: OnboardingModel

    @State private var liveKey = ""

    private var step: SetupStep {
        model.progress.current
    }

    private var status: SetupStatus {
        model.status(of: step)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: step.symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(OnboardingTheme.accent)
                    .accessibilityHidden(true)
                Text(step.title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .accessibilityAddTraits(.isHeader)
                Text(step.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440, alignment: .leading)
            }
            statusLine
            actions
            if let message = model.actionMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 34)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(step)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let text = status.message {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(OnboardingTheme.color(for: status))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 440, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            switch step {
            case .hermes:
                action("Открыть Hermes Desktop", .openHermesDesktop, prominent: !isOK)
            case .model:
                action("Открыть Hermes Desktop", .openHermesDesktop)
            case .liveKey:
                SecureField("Ключ Gemini API", text: $liveKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit { save() }
                Button("Сохранить") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(OnboardingTheme.accent)
                    .disabled(liveKey.isEmpty || model.isWorking)
            case .microphone:
                action("Разрешить микрофон", .requestMicrophone, prominent: true)
                action("Открыть настройки", .openPrivacy("Privacy_Microphone"))
            case .computer:
                action("Запросить разрешения", .requestComputer, prominent: true)
                action("Универсальный доступ", .openPrivacy("Privacy_Accessibility"))
                action("Запись экрана", .openPrivacy("Privacy_ScreenCapture"))
            case .notifications:
                action("Разрешить уведомления", .requestNotifications, prominent: true)
            case .scheduler:
                action("Запустить планировщик", .startScheduler, prominent: !isOK)
            case .tryIt:
                action("Сказать «привет»", .speakTest, prominent: true)
                action("Напоминание через минуту", .reminderTest)
            }
            if step != .tryIt, step != .liveKey || !isOK {
                action("Проверить", .recheck)
            }
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var isOK: Bool {
        if case .ok = status {
            return true
        }
        return false
    }

    private func action(_ title: String, _ action: SetupAction, prominent: Bool = false) -> some View {
        Button(title) {
            Task { await model.perform(action) }
        }
        .buttonStyle(.bordered)
        .tint(prominent ? OnboardingTheme.accent : nil)
        .disabled(model.isWorking)
    }

    private func save() {
        let key = liveKey
        liveKey = ""
        Task { await model.perform(.saveLiveKey(key)) }
    }
}
