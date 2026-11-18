@testable import RealtimeKit
import Testing

@Suite("Live startup")
struct LiveStartupTests {
    @Test("The latest hypothesis of one phrase wins")
    func latestHypothesis() {
        var startup = LiveStartup()
        startup.begin()

        startup.note("открой")
        startup.note("открой сафари")
        startup.utteranceEnded()

        #expect(startup.transcript == "открой сафари")
        #expect(startup.canHandOff)
    }

    @Test("A continuation is appended to the first phrase")
    func continuation() {
        var startup = LiveStartup()
        startup.begin()
        startup.utteranceStarted()
        startup.note("открой сафари")
        startup.utteranceEnded()

        startup.utteranceStarted()
        startup.note("и найди погоду")
        startup.utteranceEnded()

        #expect(startup.transcript == "открой сафари и найди погоду")
        #expect(startup.canHandOff)
    }

    @Test("A new phrase blocks the handoff until it is finished")
    func newPhraseBlocksHandoff() {
        var startup = LiveStartup()
        startup.begin()
        startup.note("открой сафари")
        startup.utteranceEnded()

        #expect(startup.canHandOff)

        startup.utteranceStarted()
        #expect(!startup.canHandOff)
        #expect(startup.transcript == "открой сафари")

        startup.note("и найди погоду")
        startup.utteranceEnded()
        #expect(startup.canHandOff)
    }

    @Test("The final hypothesis replaces the running one")
    func finalReplacesPartial() {
        var startup = LiveStartup()
        startup.begin()

        startup.note("открой саф")
        startup.note("Открой Safari, пожалуйста.")
        startup.utteranceEnded()

        #expect(startup.transcript == "Открой Safari, пожалуйста.")
    }

    @Test("Empty hypotheses are ignored")
    func emptyHypotheses() {
        var startup = LiveStartup()
        startup.begin()

        startup.note("   ")
        startup.note("открой сафари")
        startup.note("\n")
        startup.utteranceEnded()

        #expect(startup.transcript == "открой сафари")
    }

    @Test("A repeated final phrase is committed once")
    func noDuplicates() {
        var startup = LiveStartup()
        startup.begin()

        startup.note("спасибо")
        startup.utteranceEnded()
        startup.note("спасибо")
        startup.utteranceEnded()

        #expect(startup.transcript == "спасибо")
    }

    @Test("Skip wait opens the gate for a direct start")
    func skipWait() {
        var startup = LiveStartup()
        startup.begin(skipWait: true)

        #expect(startup.canHandOff)
        #expect(startup.isEmpty)
    }

    @Test("Nothing is collected outside a live startup")
    func ignoresEventsWhenNotTracking() {
        var startup = LiveStartup()

        startup.note("открой сафари")
        startup.utteranceEnded()

        #expect(!startup.isTracking)
        #expect(startup.isEmpty)
        #expect(!startup.canHandOff)
    }

    @Test("Finish forgets the phrase")
    func finishResets() {
        var startup = LiveStartup()
        startup.begin()
        startup.note("открой сафари")

        startup.finish()

        #expect(!startup.isTracking)
        #expect(startup.isEmpty)
        #expect(!startup.canHandOff)
    }

    @Test("A restarted ears process can force the handoff")
    func forceHandoff() {
        var startup = LiveStartup()
        startup.begin()
        startup.utteranceStarted()
        startup.note("открой сафари")

        startup.forceHandoff()

        #expect(startup.canHandOff)
        #expect(startup.transcript == "открой сафари")
    }

    @Test("A shorter fragment does not replace a full hypothesis")
    func fragmentDoesNotReplace() {
        var startup = LiveStartup()
        startup.begin()

        startup.note("открой сафари и найди погоду")
        startup.note("открой сафари")

        #expect(startup.transcript == "открой сафари и найди погоду")
    }

    @Test("A lost beginning does not replace a full hypothesis")
    func tailDoesNotReplace() {
        var startup = LiveStartup()
        startup.begin()

        startup.note("открой сафари и найди погоду")
        startup.note("и найди погоду")

        #expect(startup.transcript == "открой сафари и найди погоду")
    }

    @Test("A corrected hypothesis replaces the previous one")
    func correctionReplaces() {
        var startup = LiveStartup()
        startup.begin()

        startup.note("открой сафари и найди погоду")
        startup.note("открой Safari и найди погоду")

        #expect(startup.transcript == "открой Safari и найди погоду")
    }
}
