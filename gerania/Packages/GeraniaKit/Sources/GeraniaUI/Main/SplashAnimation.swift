import AppKit
import ImageIO

/// Кадры анимации из GIF: картинки и длительность каждого кадра.
///
/// Разбираем GIF сами (ImageIO), а не отдаём его `NSImageView`: так видно, сколько
/// кадров и сколько каждый живёт, и анимацию можно проиграть ровно один раз.
struct SplashAnimation {
    /// One frame of the animation.
    struct Frame {
        let image: NSImage
        /// How long the frame stays on the screen, in seconds.
        let duration: TimeInterval
    }

    /// Frames in the order of the animation.
    let frames: [Frame]
    /// Size of one frame in points.
    let size: NSSize
    /// The whole animation, in seconds.
    var duration: TimeInterval {
        frames.reduce(0) { $0 + $1.duration }
    }

    /// If the GIF says nothing about the pause, we use this one.
    static let defaultFrameDuration: TimeInterval = 0.1

    /// Speed of the loading animation.
    ///
    /// `1` — as fast as it is recorded in the GIF, `2` — twice as fast, `0.5` — twice
    /// as slow. Change this number to tune how fast the flower opens.
    static let playbackSpeed: Double = 2

    /// Reads the animation from the bundle of the application.
    static func load(named name: String) -> SplashAnimation? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif")
            ?? Bundle.module.url(forResource: name, withExtension: "gif")
        else {
            return nil
        }
        return load(contentsOf: url)
    }

    /// Reads the animation from a file.
    static func load(contentsOf url: URL) -> SplashAnimation? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// Decodes the bytes of a GIF into frames.
    static func decode(_ data: Data) -> SplashAnimation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [Frame] = []
        for index in 0 ..< count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            frames.append(
                Frame(
                    image: NSImage(cgImage: cgImage, size: size),
                    duration: delay(of: source, at: index) / playbackSpeed
                )
            )
        }
        guard let first = frames.first else { return nil }
        return SplashAnimation(frames: frames, size: first.image.size)
    }

    /// The pause of a frame: the GIF stores it in hundredths of a second.
    private static func delay(of source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return defaultFrameDuration
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let value = unclamped ?? clamped ?? defaultFrameDuration
        return value > 0 ? value : defaultFrameDuration
    }
}
