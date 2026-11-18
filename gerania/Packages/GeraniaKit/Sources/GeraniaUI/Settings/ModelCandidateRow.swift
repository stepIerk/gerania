import GeraniaCore
import HermesKit
import SwiftUI

/// One model of the fallback list.
///
/// The row shows what the catalog knows about the model and lets the user move
/// it, remove it or send a tiny test request. The test runs through Hermes, so
/// it checks the key and the real provider path, not a cached status.
struct ModelCandidateRow: View {
    let raw: String
    let index: Int
    let count: Int
    let capability: ModelCapabilities?
    let credential: ProviderCredentialStatus?

    @Bindable private var settings: GeraSettings
    @State private var probeResult: ModelProbeResult?
    @State private var isProbing = false

    init(
        raw: String,
        index: Int,
        count: Int,
        capability: ModelCapabilities?,
        credential: ProviderCredentialStatus?,
        settings: GeraSettings
    ) {
        self.raw = raw
        self.index = index
        self.count = count
        self.capability = capability
        self.credential = credential
        self.settings = settings
    }

    private var candidate: ModelCandidate? {
        ModelCandidate(raw: raw, defaultProvider: settings.provider)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(candidate?.model ?? raw)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if index == 0 {
                        Text("основная")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                if let candidate {
                    HStack(spacing: 4) {
                        Text(candidate.provider)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        badges
                        if let credential, !credential.isConfigured {
                            badge("нужен ключ", tint: .orange)
                                .help(credential.missingLabel ?? "Нужен ключ провайдера")
                        }
                    }
                }
            }
            Spacer(minLength: 4)
            probeBadge
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .help("Сделать выше")
            Button {
                move(by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(index >= count - 1)
            .help("Сделать ниже")
            Button {
                settings.modelCandidates.removeAll { $0 == raw }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help("Убрать из списка")
        }
    }

    @ViewBuilder
    private var badges: some View {
        if let capability {
            if capability.isLocal {
                badge("локально")
            } else if capability.isFree {
                badge("бесплатно")
            }
            if capability.supportsTools {
                badge("инструменты")
            } else {
                badge("без инструментов", tint: .orange)
                    .help("Модель не сможет открыть браузер и управлять компьютером")
            }
            if capability.supportsVision {
                badge("vision")
            }
            if let context = capability.contextLabel {
                badge(context)
            }
        } else if let candidate, ModelCapabilitiesStore.isLocalProvider(candidate.provider) {
            badge("локально")
        }
    }

    private func badge(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(tint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            }
    }

    @ViewBuilder
    private var probeBadge: some View {
        if isProbing {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16)
        } else if let probeResult {
            Image(systemName: probeResult.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(probeResult.isSuccess ? Color.green : Color.red)
                .help(probeResult.detail)
        } else if candidate != nil {
            Button("Проверить") {
                Task { await probe() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .help("Отправить модели короткий тестовый запрос")
        }
    }

    private func move(by offset: Int) {
        let target = index + offset
        guard settings.modelCandidates.indices.contains(index),
              settings.modelCandidates.indices.contains(target)
        else {
            return
        }
        settings.modelCandidates.swapAt(index, target)
    }

    private func probe() async {
        guard let candidate, !isProbing else { return }
        isProbing = true
        defer { isProbing = false }
        let config = HermesConfig(
            hermesPath: settings.hermesPath,
            provider: candidate.provider,
            model: candidate.model,
            workdir: settings.workdir,
            voicePromptPrefix: "",
            textPromptPrefix: ""
        )
        probeResult = await ModelProbe(config: config).check(candidate)
    }
}
