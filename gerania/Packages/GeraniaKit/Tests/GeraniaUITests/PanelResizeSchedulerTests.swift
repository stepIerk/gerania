import Foundation
@testable import GeraniaUI
import Testing

@Suite("Планировщик размеров панели")
@MainActor
struct PanelResizeSchedulerTests {
    @Test("Размер применяется после прохода раскладки и только последний")
    func deferAndCoalesce() async {
        let scheduler = PanelResizeScheduler()
        var applied: [CGFloat] = []

        scheduler.submit(10) { applied.append($0) }
        scheduler.submit(20) { applied.append($0) }

        // The window must not move inside the SwiftUI layout pass itself.
        #expect(applied.isEmpty)

        for _ in 0 ..< 100 where applied.isEmpty {
            await Task.yield()
        }
        #expect(applied == [20])
    }

    @Test("Новая порция после применения снова планируется")
    func submitsAgain() async {
        let scheduler = PanelResizeScheduler()
        var applied: [CGFloat] = []

        scheduler.submit(44) { applied.append($0) }
        for _ in 0 ..< 100 where applied.isEmpty {
            await Task.yield()
        }

        scheduler.submit(96) { applied.append($0) }
        for _ in 0 ..< 100 where applied.count < 2 {
            await Task.yield()
        }

        #expect(applied == [44, 96])
    }
}
