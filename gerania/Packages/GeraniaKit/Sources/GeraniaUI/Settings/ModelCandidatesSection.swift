import GeraniaCore
import HermesKit
import SwiftUI

/// Section of the settings: the models Gerania tries one after another.
///
/// The first model of the list is the primary one. The rows show what the
/// catalog knows about the model: free or paid, tools, vision, context.
public struct ModelCandidatesSection: View {
    @Bindable private var settings: GeraSettings

    @State private var newModel = ""
    @State private var selectedFromHermes = ""
    @State private var hermesModels: [String] = []
    @State private var capabilities: [String: ModelCapabilities] = [:]
    @State private var credentials: [String: ProviderCredentialStatus] = [:]

    public init(settings: GeraSettings) {
        self.settings = settings
    }

    public var body: some View {
        Section("Модели") {
            Toggle("Показывать модель в HUD", isOn: $settings.showActiveModelInHUD)

            if settings.modelCandidates.isEmpty {
                TextField("Модель по умолчанию", text: $settings.model)
                Text("Пока список пуст, Геря работает на модели по умолчанию.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(settings.modelCandidates.enumerated()), id: \.offset) { index, raw in
                    row(raw: raw, index: index)
                }
                Text("Сверху вниз: при лимите модель пропускается на 10 минут, при ошибке ключа — на сутки.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            if settings.transport == .acp {
                Text("ACP берёт модель из запущенного Hermes. Перебор работает в Авто, Gateway и One-shot.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }

            HStack {
                TextField("Добавить: provider:model", text: $newModel)
                Button("+") {
                    add(newModel)
                }
                .disabled(newModel.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Menu("Добавить бесплатную модель") {
                ForEach(Self.presets) { preset in
                    Button {
                        add(preset.candidate.id)
                    } label: {
                        Text("\(preset.candidate.id) — \(preset.note)")
                    }
                    .disabled(isAdded(preset.candidate))
                }
            }

            if !hermesModels.isEmpty {
                Picker("Из Hermes", selection: $selectedFromHermes) {
                    Text("Выберите модель…").tag("")
                    ForEach(hermesModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: selectedFromHermes) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    addFromHermes(newValue)
                    selectedFromHermes = ""
                }
            }
        }
        .task {
            await loadCatalog()
        }
    }

    private func row(raw: String, index: Int) -> some View {
        let candidate = ModelCandidate(raw: raw, defaultProvider: settings.provider)
        return ModelCandidateRow(
            raw: raw,
            index: index,
            count: settings.modelCandidates.count,
            capability: candidate.flatMap(capability),
            credential: candidate.flatMap { credentials[$0.provider] },
            settings: settings
        )
    }

    private func add(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let candidate = ModelCandidate(raw: trimmed, defaultProvider: settings.provider)
        else {
            return
        }
        if !isAdded(candidate) {
            settings.modelCandidates.append(candidate.id)
            refreshCredentials(for: [candidate])
        }
        newModel = ""
    }

    private func addFromHermes(_ model: String) {
        let candidate = ModelCandidate(provider: settings.provider, model: model)
        if !isAdded(candidate) {
            settings.modelCandidates.append(candidate.id)
            refreshCredentials(for: [candidate])
        }
    }

    private func isAdded(_ candidate: ModelCandidate) -> Bool {
        settings.modelCandidates.contains { raw in
            ModelCandidate(raw: raw, defaultProvider: settings.provider)?.id == candidate.id
        }
    }

    private func capability(for candidate: ModelCandidate) -> ModelCapabilities? {
        capabilities[Self.key(candidate)]
    }

    private func loadCatalog() async {
        let store = ModelCapabilitiesStore()
        let all = await store.allCapabilities()
        var map: [String: ModelCapabilities] = [:]
        for capability in all {
            map["\(capability.provider):\(capability.model.lowercased())"] = capability
        }
        capabilities = map
        hermesModels = HermesModelCatalog.models(
            homeDirectory: NSHomeDirectory(),
            provider: settings.provider
        )
        refreshCredentials(for: modelRows)
    }

    private func refreshCredentials(for candidates: [ModelCandidate]) {
        for provider in Set(candidates.map(\.provider)) where credentials[provider] == nil {
            credentials[provider] = ProviderCredentials.status(provider: provider)
        }
    }

    private var modelRows: [ModelCandidate] {
        settings.modelCandidates.compactMap {
            ModelCandidate(raw: $0, defaultProvider: settings.provider)
        }
    }

    private static func key(_ candidate: ModelCandidate) -> String {
        "\(ModelCapabilitiesStore.normalizeProvider(candidate.provider)):\(candidate.model.lowercased())"
    }

    private struct Preset: Identifiable {
        let candidate: ModelCandidate
        let note: String

        var id: String {
            candidate.id
        }
    }

    /// Free models that work with the toolsets enabled in Gerania.
    private static let presets: [Preset] = [
        Preset(
            candidate: ModelCandidate(provider: "gemini", model: "gemini-2.5-flash-lite"),
            note: "бесплатный лимит, быстрая"
        ),
        Preset(
            candidate: ModelCandidate(provider: "gemini", model: "gemini-2.5-flash"),
            note: "бесплатный лимит, умнее"
        ),
        Preset(
            candidate: ModelCandidate(provider: "openrouter", model: "openrouter/free"),
            note: "нужен ключ OpenRouter"
        ),
        Preset(
            candidate: ModelCandidate(provider: "openrouter", model: "google/gemma-4-31b-it:free"),
            note: "нужен ключ OpenRouter"
        ),
        Preset(
            candidate: ModelCandidate(provider: "openrouter", model: "nvidia/nemotron-3.5-super-vl:free"),
            note: "нужен ключ OpenRouter, vision"
        ),
        Preset(
            candidate: ModelCandidate(provider: "zai", model: "glm-4.7-flash"),
            note: "бесплатный лимит, нужен ключ ZAI"
        ),
        Preset(
            candidate: ModelCandidate(provider: "ollama", model: "qwen3:8b"),
            note: "локально, без ключа"
        ),
    ]
}
