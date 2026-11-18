import AppKit
import GeraniaCore
import HermesKit
import SwiftUI

/// Settings section: may Gerania drive the computer through cua-driver?
///
/// The TCC grants belong to `CuaDriver.app` (`com.trycua.driver`), not to
/// Gerania: the driver performs the clicks and the screen capture. The card
/// explains that and links to the right panes of System Settings instead of
/// sending the user to search for the toggle.
public struct ComputerUseSection: View {
    @Bindable private var settings: GeraSettings

    @State private var status: ComputerUseStatus?
    @State private var isLoading = false
    @State private var isRequesting = false
    @State private var message: String?

    public init(settings: GeraSettings) {
        self.settings = settings
    }

    public var body: some View {
        Section("Компьютер") {
            HStack(spacing: 7) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button("Проверить") {
                    Task { await refresh() }
                }
                .disabled(isLoading || isRequesting)
            }

            if let status, status.error == nil {
                LabeledContent("Драйвер", value: status.driverLabel)
                permissionRow(
                    "Универсальный доступ",
                    granted: status.accessibility,
                    service: "Privacy_Accessibility"
                )
                permissionRow(
                    "Запись экрана",
                    granted: status.screenRecording,
                    service: "Privacy_ScreenCapture"
                )
            }

            if let message {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if status?.isReady == false {
                HStack {
                    Button("Запросить разрешения") {
                        Task { await requestPermissions() }
                    }
                    .disabled(isRequesting || isLoading)
                    Button("Открыть настройки") {
                        openSystemSettings()
                    }
                }
            }

            Text(
                "Права выдаются приложению CuaDriver.app (com.trycua.driver), а не Герании: "
                    + "драйвер кликает и снимает экран. После выдачи вернитесь и нажмите «Проверить»."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
        .task {
            if status == nil {
                await refresh()
            }
        }
    }

    private var indicatorColor: Color {
        guard let status else { return .secondary }
        if status.isReady {
            return .green
        }
        return status.error == nil && status.isInstalled ? .orange : .red
    }

    private var title: String {
        guard let status else { return "Проверяю драйвер…" }
        return status.summary
    }

    private func permissionRow(_ title: String, granted: Bool?, service: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Image(systemName: symbol(for: granted))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color(for: granted))
                Text(label(for: granted))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if granted != true {
                    Button("Открыть") {
                        openSystemSettings(service: service)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }
        }
    }

    private func symbol(for granted: Bool?) -> String {
        switch granted {
        case true: "checkmark.circle.fill"
        case false: "xmark.circle.fill"
        case nil: "questionmark.circle"
        }
    }

    private func color(for granted: Bool?) -> Color {
        switch granted {
        case true: .green
        case false: .red
        case nil: .secondary
        }
    }

    private func label(for granted: Bool?) -> String {
        switch granted {
        case true: "разрешено"
        case false: "нет"
        case nil: "неизвестно"
        }
    }

    private func requestPermissions() async {
        guard !isRequesting else { return }
        isRequesting = true
        message = nil
        let error = await ComputerUseInspector(config: config).requestPermissions()
        message = error
        isRequesting = false
        await refresh()
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        status = await ComputerUseInspector(config: config).inspect()
    }

    private var config: HermesConfig {
        HermesConfig(
            hermesPath: settings.hermesPath,
            provider: settings.provider,
            model: settings.model,
            workdir: settings.workdir,
            voicePromptPrefix: "",
            textPromptPrefix: ""
        )
    }

    private func openSystemSettings(service: String = "Privacy_Accessibility") {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(service)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
