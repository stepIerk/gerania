import Foundation

public extension HermesConfig {
    /// Which Hermes tool acts on the Mac.
    ///
    /// Without it the model often reached for `browser_cdp` to open a site or
    /// click, and that tool answers «No CDP endpoint is available» / «not a
    /// WebSocket URL» until Chrome is attached with `/browser connect`. The
    /// person saw «не настроен URL» and nothing happened. `computer_use`
    /// (cua-driver) works on any app, the browser included, without setup.
    static let toolRoutingHint = "[Гера] Действия на этом Mac — открыть приложение или сайт, кликнуть, "
        + "напечатать, посмотреть экран — выполняй инструментом computer_use. "
        + "browser_cdp вызывай, только если Chrome уже подключён через /browser connect. "
}
