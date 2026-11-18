import Foundation
import GeraniaCore
import HermesKit
import Observation

/// State of the «Планы» tab.
///
/// Reading is a plain parse of `jobs.json`; every action goes through
/// `hermes cron ...`, so the scheduler keeps its locks and validation. After an
/// action the list is reloaded instead of mutated locally: Hermes may have
/// recomputed the next run or changed the state.
@MainActor
@Observable
public final class PlansModel {
    public private(set) var jobs: [CronJob] = []
    public private(set) var outputs: [CronOutput] = []
    public private(set) var isLoading = false
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var statusMessage: String?

    /// Folder with `jobs.json` and `output/`; shown in the tab footer.
    public nonisolated let directory: URL
    private let store: CronJobsStore

    public init(store: CronJobsStore) {
        self.store = store
        directory = store.directory
    }

    public convenience init(settings: GeraSettings) {
        self.init(store: CronJobsStore(config: HermesConfig(
            hermesPath: settings.hermesPath,
            provider: settings.provider,
            model: settings.model,
            workdir: settings.workdir,
            voicePromptPrefix: "",
            textPromptPrefix: ""
        )))
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            jobs = try await store.load()
            errorMessage = nil
        } catch {
            jobs = []
            errorMessage = message(for: error)
        }
        outputs = CronOutputStore.recent(in: directory)
    }

    public func pause(_ job: CronJob) async -> Bool {
        await perform("«\(job.name)» на паузе") {
            try await self.store.pause(job.id)
        }
    }

    public func resume(_ job: CronJob) async -> Bool {
        await perform("«\(job.name)» снова по расписанию") {
            try await self.store.resume(job.id)
        }
    }

    public func runNow(_ job: CronJob) async -> Bool {
        await perform("«\(job.name)» запустится на ближайшем тике") {
            try await self.store.runNow(job.id)
        }
    }

    public func remove(_ job: CronJob) async -> Bool {
        await perform("«\(job.name)» удалён") {
            try await self.store.remove(job.id)
        }
    }

    public func create(_ request: CronJobRequest) async -> Bool {
        await perform("План создан") {
            try await self.store.create(request)
        }
    }

    public func dismissMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    private func perform(
        _ success: String,
        _ operation: () async throws -> Void
    ) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
            statusMessage = success
            errorMessage = nil
            await reload()
            return true
        } catch {
            statusMessage = nil
            errorMessage = message(for: error)
            return false
        }
    }

    private func reload() async {
        do {
            jobs = try await store.load()
        } catch {
            errorMessage = message(for: error)
        }
        outputs = CronOutputStore.recent(in: directory)
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
