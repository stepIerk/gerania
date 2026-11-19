import AppKit
import GeraniaCore
import HermesKit

/// Actions of the HUD that the orchestrator has to carry out.
extension AppModel {
    func perform(_ action: HUDAction) {
        switch action {
        case .copyAnswer:
            copyAnswer()
        case .expandAnswer:
            panels?.presentDetail()
        case .continueChat:
            panels?.presentInput(prefill: "", showChats: false)
        case .openInDesktop:
            openInDesktop(sessionID: settings.lastSessionID)
        case .openInTerminal:
            openInTerminal(sessionID: settings.lastSessionID)
        case .toggleSpeech:
            toggleSpeech()
        case .closePanel:
            panels?.dismissDetail()
            dispatch(.dismissed)
        case .togglePin:
            hud.isPinned.toggle()
        case .retry:
            if let lastPrompt {
                ask(lastPrompt)
            }
        case let .answer(request, value):
            Task { await respond(to: request, with: value) }
        case .stopComputerUse:
            Log.ui.info("computer use stopped from the HUD")
            stop()
        case .stopAnswer:
            Log.ui.info("answer stopped from the HUD")
            stopAnswer()
        }
    }

    private func copyAnswer() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hud.streamedText, forType: .string)
        Log.ui.info("answer copied to the pasteboard")
    }

    private func toggleSpeech() {
        // The voice bridge arrives with the voice stage; until then the state only flips.
        if state == .speaking {
            dispatch(.speechFinished)
        } else {
            dispatch(.speechStarted)
        }
    }
}
