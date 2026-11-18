import AppKit
@testable import GeraniaUI
import SwiftUI
import Testing

@Suite("SwiftUI внутри плавающей панели")
@MainActor
struct FloatingPanelHostTests {
    @Test("Hosting view не является contentView и растягивается вместе с панелью")
    func hostLivesBelowContentView() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 44),
            acceptsKey: false
        )
        let host = panel.host(Text("Гера"))

        // SwiftUI's app lifecycle resizes a window whose contentView is the
        // hosting view; the panel controller must stay the only owner.
        #expect(panel.contentView !== host)
        #expect(host.superview === panel.contentView)
        #expect(host.autoresizingMask.contains(.width))
        #expect(host.autoresizingMask.contains(.height))
        #expect(host.frame.size == panel.contentView?.bounds.size)

        panel.setFrame(NSRect(x: 0, y: 0, width: 420, height: 180), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()

        #expect(host.frame.size == panel.contentView?.bounds.size)
        #expect(host.frame.size.height == 180)
    }
}
