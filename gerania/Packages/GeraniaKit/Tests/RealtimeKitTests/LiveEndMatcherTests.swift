@testable import RealtimeKit
import Testing

@Suite("Live end matcher")
struct LiveEndMatcherTests {
    @Test("Polite goodbyes end the dialog")
    func goodbyes() {
        #expect(LiveEndMatcher.isEnd("Спасибо"))
        #expect(LiveEndMatcher.isEnd("Большое спасибо, Гера!"))
        #expect(LiveEndMatcher.isEnd("Ну всё, спасибо"))
        #expect(LiveEndMatcher.isEnd("Спасибо, что помогла"))
        #expect(LiveEndMatcher.isEnd("Спасибо за помощь"))
        #expect(LiveEndMatcher.isEnd("Это всё"))
        #expect(LiveEndMatcher.isEnd("На этом всё"))
        #expect(LiveEndMatcher.isEnd("Больше ничего не нужно"))
        #expect(LiveEndMatcher.isEnd("Пока"))
        #expect(LiveEndMatcher.isEnd("До свидания"))
        #expect(LiveEndMatcher.isEnd("До встречи"))
        #expect(LiveEndMatcher.isEnd("Спокойной ночи"))
        #expect(LiveEndMatcher.isEnd("Закончили"))
    }

    @Test("A continuation is not a goodbye")
    func continuation() {
        #expect(!LiveEndMatcher.isEnd("Спасибо, а теперь открой Safari"))
        #expect(!LiveEndMatcher.isEnd("Спасибо, что помогла с файлом"))
        #expect(!LiveEndMatcher.isEnd("Спасибо за файл, но нужно ещё"))
        #expect(!LiveEndMatcher.isEnd("Всё готово?"))
        #expect(!LiveEndMatcher.isEnd("Мне нужно всё"))
        #expect(!LiveEndMatcher.isEnd("Расскажи, что нового"))
        #expect(!LiveEndMatcher.isEnd("Ничего"))
        #expect(!LiveEndMatcher.isEnd("Хорошо"))
        #expect(!LiveEndMatcher.isEnd("Пожалуйста"))
        #expect(!LiveEndMatcher.isEnd(""))
    }

    @Test("«Пока не» means not yet, not goodbye")
    func notYet() {
        #expect(!LiveEndMatcher.isEnd("Пока не надо"))
        #expect(!LiveEndMatcher.isEnd("Пока нет"))
        #expect(!LiveEndMatcher.isEnd("Пока что не нужно"))
    }
}

@Suite("Live end detector")
struct LiveEndDetectorTests {
    @Test("The decision is made on the whole turn")
    func wholeTurn() {
        var detector = LiveEndDetector()

        detector.addUser("ну")
        detector.addUser("спасибо")

        let ended = detector.finishTurn()
        #expect(ended)
        #expect(detector.currentText.isEmpty)
    }

    @Test("A new request keeps the dialog open")
    func newRequest() {
        var detector = LiveEndDetector()

        detector.addUser("спасибо")
        detector.addUser("а теперь открой Safari")

        let ended = detector.finishTurn()
        #expect(!ended)
    }

    @Test("Reset forgets the current turn")
    func reset() {
        var detector = LiveEndDetector()
        detector.addUser("спасибо")

        detector.reset()

        #expect(detector.currentText.isEmpty)
        let ended = detector.finishTurn()
        #expect(!ended)
    }

    @Test("The buffer keeps only the tail")
    func capped() {
        var detector = LiveEndDetector()

        detector.addUser(String(repeating: "слово ", count: 100))

        #expect(detector.currentText.count <= 300)
    }
}
