@testable import RealtimeKit
import Testing

@Suite("Live stop matcher")
struct LiveStopMatcherTests {
    @Test("Explicit stop phrases stop the dialog")
    func explicitStops() {
        #expect(LiveStopMatcher.isStop("стоп"))
        #expect(LiveStopMatcher.isStop("Гера, стоп!"))
        #expect(LiveStopMatcher.isStop("остановись, пожалуйста"))
        #expect(LiveStopMatcher.isStop("хватит"))
        #expect(LiveStopMatcher.isStop("до свидания"))
        #expect(LiveStopMatcher.isStop("не надо"))
        #expect(LiveStopMatcher.isStop("Гера, замолчи"))
        #expect(LiveStopMatcher.isStop("нет, стоп"))
    }

    @Test("Ordinary answers are not stop phrases")
    func ordinaryAnswers() {
        #expect(!LiveStopMatcher.isStop("нет"))
        #expect(!LiveStopMatcher.isStop("ничего"))
        #expect(!LiveStopMatcher.isStop("останови музыку"))
        #expect(!LiveStopMatcher.isStop("расскажи, что нового"))
        #expect(!LiveStopMatcher.isStop("Гера, открой Safari"))
        #expect(!LiveStopMatcher.isStop(""))
        #expect(!LiveStopMatcher.isStop("пожалуйста"))
        #expect(!LiveStopMatcher.isStop("надо"))
        #expect(!LiveStopMatcher.isStop("не"))
        #expect(!LiveStopMatcher.isStop("до"))
    }

    @Test("Punctuation and ё are normalized")
    func normalization() {
        #expect(LiveStopMatcher.normalize("Гёра, всё!") == ["гера", "все"])
        #expect(LiveStopMatcher.isStop("Всё, хватит."))
    }

    @Test("Whisper mishearing of the wake word before a stop is forgiven")
    func misheardWakeWord() {
        #expect(LiveStopMatcher.isStop("Гиро, стоп"))
        #expect(LiveStopMatcher.isStop("Гира, остановись"))
        #expect(LiveStopMatcher.isStop("гэра, хватит"))
        #expect(LiveStopMatcher.isStop("герания, замолчи"))
    }

    @Test("Short stop words of the classic pipeline work in live mode")
    func shortStops() {
        #expect(LiveStopMatcher.isStop("стой"))
        #expect(LiveStopMatcher.isStop("отбой"))
        #expect(LiveStopMatcher.isStop("отставить"))
        #expect(LiveStopMatcher.isStop("замолкни"))
    }
}
