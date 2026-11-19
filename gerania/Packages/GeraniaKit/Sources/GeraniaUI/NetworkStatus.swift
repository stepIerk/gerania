import Foundation
import GeraniaCore
import Network
import Observation

/// Whether the Mac has a route to the internet, from `NWPathMonitor`.
///
/// Cloud models and Gemini Live need the network. Knowing it is gone lets Gera
/// say «нет интернета» instead of a transport error after a long timeout, and
/// skip the live dialog right away.
@MainActor
@Observable
public final class NetworkStatus {
    public static let shared = NetworkStatus()

    /// Optimistic until the first update: a false «offline» would block Gera.
    public private(set) var isOnline = true

    @ObservationIgnored private var monitor: NWPathMonitor?

    private init() {}

    public var isOffline: Bool {
        !isOnline
    }

    public func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                NetworkStatus.shared.update(online: online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "gerania.network"))
        self.monitor = monitor
    }

    private func update(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        Log.app.notice("network: \(online ? "online" : "offline", privacy: .public)")
    }

    /// The HUD text for a failed request while offline.
    public static let offlineMessage = "Нет подключения к интернету: облачная модель и живой диалог недоступны. "
        + "Проверьте Wi‑Fi — Гера снова ответит, когда сеть вернётся."
}
