import CoreGraphics
import Foundation
import GeraniaCore
import GeraniaUI
import Testing

@Suite("PanelPlacement")
struct PanelPlacementTests {
    /// Display with a camera housing: the menu bar strip is 38 pt high.
    private let notchScreen = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        safeAreaTop: 0,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 640, height: 38),
        auxiliaryTopRightArea: CGRect(x: 872, y: 944, width: 640, height: 38)
    )

    /// External display without a notch and with the Dock at the bottom.
    private let flatScreen = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1030),
        safeAreaTop: 0,
        auxiliaryTopLeftArea: .zero,
        auxiliaryTopRightArea: .zero
    )

    private let size = CGSize(width: 400, height: 120)

    @Test("Notch screen is detected by the auxiliary areas")
    func notchDetection() {
        #expect(notchScreen.hasNotch)
        #expect(!flatScreen.hasNotch)
        #expect(notchScreen.menuBarHeight == 38)
        #expect(flatScreen.menuBarHeight == 25)
    }

    @Test("Notch panel hangs from the top edge of the screen")
    func notchPlacement() {
        let origin = PanelPlacement.origin(position: .notch, panelSize: size, screen: notchScreen)
        let expectedY: CGFloat = 862
        let expectedX: CGFloat = 556

        #expect(origin.y == expectedY)
        #expect(origin.x == expectedX)
    }

    @Test("Panel on a display without a notch keeps a gap under the menu bar")
    func notchPlacementWithoutNotch() {
        let origin = PanelPlacement.origin(position: .notch, panelSize: size, screen: flatScreen)
        let expectedY: CGFloat = 927
        let expectedX: CGFloat = 760

        #expect(origin.y == expectedY)
        #expect(origin.x == expectedX)
    }

    @Test("Top right placement keeps the corner margin")
    func topRightPlacement() {
        let origin = PanelPlacement.origin(position: .topRight, panelSize: size, screen: flatScreen)
        let expectedX: CGFloat = 1508
        let expectedY: CGFloat = 923

        #expect(origin.x == expectedX)
        #expect(origin.y == expectedY)
    }

    @Test("Menu bar icon placement is clamped to the visible frame")
    func menuBarIconPlacement() {
        let iconRect = CGRect(x: 1880, y: 1055, width: 40, height: 25)
        let origin = PanelPlacement.origin(
            position: .belowMenuBarIcon,
            panelSize: size,
            screen: flatScreen,
            menuBarIconRect: iconRect
        )
        let expectedX: CGFloat = 1520
        let expectedY: CGFloat = 929

        #expect(origin.x == expectedX)
        #expect(origin.y == expectedY)
    }

    @Test("Without an icon rect the panel falls back to the top right corner")
    func menuBarIconFallback() {
        let origin = PanelPlacement.origin(
            position: .belowMenuBarIcon,
            panelSize: size,
            screen: flatScreen,
            menuBarIconRect: nil
        )
        let expected = PanelPlacement.origin(position: .topRight, panelSize: size, screen: flatScreen)

        #expect(origin == expected)
    }
}
