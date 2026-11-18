import GeraniaCore
import SwiftUI

/// The first-run wizard: the stem of steps on the left, the current step on
/// the right and the navigation at the bottom. Every step can be skipped.
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                OnboardingStemView(progress: model.progress) { step in
                    model.select(step)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                OnboardingStepView(model: model)
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            bottomBar
        }
        .background(OnboardingTheme.background)
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 760, minHeight: 500)
        .task { await model.checkAll() }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text(counter)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.55))
            if !model.progress.blockers.isEmpty {
                Text(blockerText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(OnboardingTheme.failure)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Назад") {
                model.back()
            }
            .disabled(model.progress.current == SetupStep.allCases.first)
            .keyboardShortcut(.leftArrow, modifiers: .command)
            if model.progress.isLastStep {
                Button("Готово") {
                    model.finish()
                }
                .buttonStyle(.borderedProminent)
                .tint(OnboardingTheme.accent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Пропустить") {
                    model.skip()
                }
                .help("Шаг можно настроить позже: меню Геры → «Мастер настройки…»")
                Button("Дальше") {
                    model.next()
                }
                .buttonStyle(.borderedProminent)
                .tint(OnboardingTheme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var counter: String {
        "Готово \(model.progress.readyCount) из \(SetupStep.allCases.count)"
    }

    private var blockerText: String {
        let names = model.progress.blockers.map { "«\($0.title)»" }.joined(separator: " и ")
        let noun = model.progress.blockers.count == 1 ? "шага" : "шагов"
        return "Без \(noun) \(names) Гера не сможет отвечать."
    }
}
