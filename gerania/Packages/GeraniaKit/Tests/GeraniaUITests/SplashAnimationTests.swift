import Foundation
@testable import GeraniaUI
import Testing

@Suite("Анимация загрузки")
struct SplashAnimationTests {
    /// Один пиксель: настоящий GIF, только крошечный.
    private let tinyGIF = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7") ?? Data()

    @Test("GIF разбирается на кадры")
    func decodesFrames() throws {
        let animation = try #require(SplashAnimation.decode(tinyGIF))

        #expect(animation.frames.count == 1)
        #expect(animation.size.width == 1)
        #expect(animation.size.height == 1)
    }

    @Test("Кадр без паузы живёт стандартное время")
    func usesDefaultDelay() throws {
        let animation = try #require(SplashAnimation.decode(tinyGIF))

        #expect(animation.frames[0].duration == SplashAnimation.defaultFrameDuration / SplashAnimation.playbackSpeed)
        #expect(animation.duration > 0)
    }

    @Test("Скорость меняет длительность анимации")
    func speedScalesDuration() throws {
        let animation = try #require(SplashAnimation.decode(tinyGIF))

        // Больше скорость — меньше времени на кадр.
        #expect(animation.duration * SplashAnimation.playbackSpeed == SplashAnimation.defaultFrameDuration)
        #expect(SplashAnimation.playbackSpeed > 0)
    }

    @Test("Битые данные не ломают приложение")
    func brokenData() {
        #expect(SplashAnimation.decode(Data("not a gif".utf8)) == nil)
        #expect(SplashAnimation.decode(Data()) == nil)
    }
}
