import GeraniaCore
import SwiftUI

/// The window of the application: the welcome screen and the settings.
///
/// While the application starts, the window shows the animation of the flower on a
/// black background. When the animation ends, it fades away and the settings appear.
public struct MainWindowView: View {
    private let model: AppModel
    private let chats: ChatsModel
    private let onLaunch: () -> Void
    private let onStop: () -> Void
    private let onLoadingFinished: () -> Void

    @State private var isLoading = true
    @State private var animation: SplashAnimation?

    public init(
        model: AppModel,
        chats: ChatsModel,
        onLaunch: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onLoadingFinished: @escaping () -> Void
    ) {
        self.model = model
        self.chats = chats
        self.onLaunch = onLaunch
        self.onStop = onStop
        self.onLoadingFinished = onLoadingFinished
    }

    public var body: some View {
        ZStack {
            if isLoading {
                loading
                    .transition(.opacity)
            } else {
                content
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .task { await prepareAnimation() }
    }

    /// The loading screen: the black background with the flower.
    @ViewBuilder
    private var loading: some View {
        if let animation {
            SplashView(animation: animation, onFinished: finishLoading)
        } else {
            Color.black
        }
    }

    /// The welcome screen and the settings.
    private var content: some View {
        VStack(spacing: 0) {
            WelcomeHeroView(model: model, onLaunch: onLaunch, onStop: onStop)
            Divider()
            SettingsTabs(
                settings: model.settings,
                chats: chats,
                auditLog: model.auditLog,
                memory: model.memory
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Looks for the animation of the loading screen.
    private func prepareAnimation() async {
        guard let animation = SplashAnimation.load(named: "GeraLoading") else {
            Log.ui.info("loading animation not found: GeraLoading")
            finishLoading()
            return
        }
        self.animation = animation
    }

    /// The animation is over: the settings appear under it.
    private func finishLoading() {
        onLoadingFinished()
        withAnimation(.easeOut(duration: 0.35)) {
            isLoading = false
        }
    }
}
