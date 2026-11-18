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
    /// The Hermes cron ticker, from `cron/ticker_heartbeat`.
    public private(set) var scheduler: CronSchedulerStatus = .notRunning
    /// Whether banners about finished plans can appear.
    public private(set) var notifications: NotificationAccess = .unknown

    /// Folder with `jobs.json` and `output/`; shown in the tab footer.
    public nonisolated let directory: URL
    private let store: CronJobsStore
    /// Reads the notification permission; `nil` in the tests.
    private let notificationAccess: (@Sendable () async -> NotificationAccess)?
    /// Asks for the permission; `nil` in the tests.
    private let notificationRequest: (@Sendable () async -> NotificationAccess)?

    public init(
        store: CronJobsStore,
        notificationAccess: (@Sendable () async -> NotificationAccess)? = nil,
        notificationRequest: (@Sendable () async -> NotificationAccess)? = nil
    ) {
        self.store = store
        self.notificationAccess = notificationAccess
        self.notificationRequest = notificationRequest
        directory = store.directory
    }

    public convenience init(settings: GeraSettings) {
        self.init(
            store: CronJobsStore(config: HermesConfig(
                hermesPath: settings.hermesPath,
                provider: settings.provider,
                model: settings.model,
                workdir: settings.workdir,
                voicePromptPrefix: "",
                textPromptPrefix: ""
            )),
            notificationAccess: { await CronNotifier.access() },
            notificationRequest: { await CronNotifier.requestIfNeeded() }
        )
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
        await refreshDelivery()
    }

    /// Re-reads the scheduler heartbeat and the notification permission.
    public func refreshDelivery() async {
        scheduler = CronSchedulerStatus.read(cronDirectory: directory)
        if let notificationAccess {
            notifications = await notificationAccess()
        }
    }

    /// Starts the Hermes gateway, which runs the cron ticker.
    @discardableResult
    public func startScheduler() async -> Bool {
        let started = await perform("Планировщик Hermes запущен") {
            try await self.store.ensureGateway()
        }
        guard started else { return false }
        // The ticker stamps its heartbeat on the first loop, a moment after start.
        try? await Task.sleep(for: .seconds(2))
        await refreshDelivery()
        if !scheduler.isRunning {
            statusMessage = "Gateway запущен, ждём первый тик планировщика (до минуты)."
        }
        return true
    }

    public func requestNotifications() async {
        guard let notificationRequest else { return }
        notifications = await notificationRequest()
        if notifications == .denied {
            CronNotifier.openSystemSettings()
        }
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
        let created = await perform("План создан") {
            try await self.store.create(request)
        }
        if created, !scheduler.isRunning {
            statusMessage = "План создан, но планировщик Hermes не запущен: он не сработает, "
                + "пока вы не нажмёте «Запустить планировщик»."
        }
        return created
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
        scheduler = CronSchedulerStatus.read(cronDirectory: directory)
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
