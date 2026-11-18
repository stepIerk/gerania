import Foundation

/// Pure state machine. No I/O, no clocks: the caller passes time in actions.
public func reduce(state: GeraState, action: GeraAction) -> (GeraState, [Effect]) {
    switch action {
    case let .wake(at):
        let bargeIn = state.isInterruptible
        var effects: [Effect] = [.showPanel, .playSound(.wake), .startListening]
        if case .speaking = state {
            effects.insert(.stopSpeaking, at: 0)
        }
        if case .transcribing = state {
            effects.insert(.cancelTranscription, at: 0)
        }
        if bargeIn {
            effects.insert(.interrupt, at: 0)
        }
        return (.listening(deadline: at + 8), effects)

    case .listenTimedOut:
        guard case .listening = state else { return (state, []) }
        return (.idle, [.stopListening, .hidePanel(after: 0)])

    case .transcriptionStarted:
        guard case .listening = state else { return (state, []) }
        return (.transcribing, [.stopListening])

    case let .transcriptionFailed(message):
        guard case .transcribing = state else { return (state, []) }
        return (.error(message), [.playSound(.error), .hidePanel(after: 4)])

    case .turnStarted:
        return (.thinking(tools: []), [.showPanel, .playSound(.sent)])

    case .promptSubmitted:
        switch state {
        case .listening, .transcribing, .thinking, .streaming:
            return (.thinking(tools: []), [.showPanel, .playSound(.sent)])
        default:
            return (state, [])
        }

    case .textStarted, .textDelta:
        switch state {
        case .thinking, .streaming, .speaking:
            return (.streaming, [.showPanel])
        default:
            return (state, [])
        }

    case .reasoningDelta:
        guard case .thinking = state else { return (state, []) }
        return (state, [])

    case let .toolStarted(chip):
        switch state {
        case let .thinking(tools):
            return (.thinking(tools: tools + [chip]), [])
        case .streaming:
            return (.thinking(tools: [chip]), [])
        default:
            return (state, [])
        }

    case let .toolOutput(id, imagePath, summary):
        guard case let .thinking(tools) = state else { return (state, []) }
        let updated = tools.map { chip in
            chip.id == id ? chip.withOutput(imagePath: imagePath, summary: summary) : chip
        }
        return (.thinking(tools: updated), [])

    case let .toolFinished(id, ok):
        guard case let .thinking(tools) = state else { return (state, []) }
        let updated = tools.map { $0.id == id ? $0.finished(ok: ok) : $0 }
        return (.thinking(tools: updated), [])

    case let .serverRequest(request):
        switch state {
        case .idle, .done, .error:
            return (state, [])
        default:
            return (.awaitingApproval(request), [.showPanel])
        }

    case .serverRequestAnswered:
        guard case .awaitingApproval = state else { return (state, []) }
        return (.thinking(tools: []), [])

    case .completed:
        guard state.isBusy || state != .idle else { return (state, []) }
        if case .listening = state {
            return (state, [])
        }
        return (.done, [.playSound(.done), .hidePanel(after: 6)])

    case .cancelled:
        return (.idle, [.hidePanel(after: 0), .stopSpeaking])

    case .speechStarted:
        switch state {
        case .done, .streaming, .thinking:
            return (.speaking, [])
        default:
            return (state, [])
        }

    case .speechFinished:
        guard case .speaking = state else { return (state, []) }
        return (.done, [])

    case .stop:
        switch state {
        case .idle:
            return (state, [])
        default:
            return (.idle, [.stopListening, .cancelTranscription, .stopSpeaking, .interrupt, .hidePanel(after: 0)])
        }

    case let .failed(message):
        return (.error(message), [.playSound(.error), .hidePanel(after: 4)])

    case .dismissed:
        switch state {
        case .idle, .done, .error:
            return (.idle, [.hidePanel(after: 0)])
        default:
            // Closing the HUD also stops whatever is running: listening, the turn
            // and the speech must not continue without a visible panel.
            return (
                .idle,
                [.stopListening, .cancelTranscription, .stopSpeaking, .interrupt, .hidePanel(after: 0)]
            )
        }
    }
}
