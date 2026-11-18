// Собирает мастер-иконку приложения из картинки пользователя.
//
// Исходник может быть любого размера и не квадратным: он центрируется, вписывается
// в квадрат и обрезается по белому фону (прозрачность). Дальше цветок кладётся на
// тёмный macOS-сквиркл — так иконка совпадает с чёрными панелями приложения.
//
// Запуск: swift scripts/make_icon.swift <source.png> <master.png>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Размер мастер-иконки: столько пикселей нужно всем размерам каталога.
let canvasSize = 1024
/// Сторона сквиркла внутри холста: поля 100 пикселей, как в сетке иконок macOS.
let bodySide = 824.0
/// Насколько цветок занимает ширину сквиркла.
let artInset = 1.0

// MARK: - Загрузка и подготовка исходника

func loadImage(at path: String) -> CGImage? {
    guard let data = FileManager.default.contents(atPath: path) as CFData? else { return nil }
    guard let source = CGImageSourceCreateWithData(data, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Квадратная середина исходника.
func squareCrop(_ image: CGImage) -> CGImage? {
    let side = min(image.width, image.height)
    let crop = CGRect(
        x: (image.width - side) / 2,
        y: (image.height - side) / 2,
        width: side,
        height: side
    )
    return image.cropping(to: crop)
}

/// Убирает белый фон: пиксели, близкие к белому, становятся прозрачными.
///
/// Порог мягкий, чтобы край цветка не рассыпался на полупрозрачные крупинки.
func makeAlpha(_ image: CGImage) -> CGImage? {
    let side = image.width
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    guard let context = CGContext(
        data: &pixels,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

    let threshold = 34.0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let red = Double(pixels[index])
        let green = Double(pixels[index + 1])
        let blue = Double(pixels[index + 2])
        let darkest = min(red, min(green, blue))
        let raw = max(0, min(1, (255 - darkest) / threshold))
        // Мягкая кривая: середина границы полупрозрачная, тело цвета плотное.
        let alpha = raw * raw * (3 - 2 * raw)
        let scale = alpha
        pixels[index] = UInt8(red * scale)
        pixels[index + 1] = UInt8(green * scale)
        pixels[index + 2] = UInt8(blue * scale)
        pixels[index + 3] = UInt8(alpha * 255)
    }

    guard let result = context.makeImage() else { return nil }
    return result
}

// MARK: - Геометрия

/// Сквиркл macOS: почти прямоугольник с очень круглыми углами.
func squirclePath(in rect: CGRect, exponent: Double = 6, samples: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let halfWidth = rect.width / 2
    let halfHeight = rect.height / 2
    let power = 2 / exponent
    for index in 0...samples {
        let angle = Double(index) / Double(samples) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = rect.midX + halfWidth * copysign(pow(abs(cosine), power), cosine)
        let y = rect.midY + halfHeight * copysign(pow(abs(sine), power), sine)
        let point = CGPoint(x: x, y: y)
        if index == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    path.closeSubpath()
    return path
}

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

// MARK: - Сборка

func makeMaster(from source: CGImage) -> CGImage? {
    let canvas = CGFloat(canvasSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    let body = CGRect(
        x: (canvas - bodySide) / 2,
        y: (canvas - bodySide) / 2,
        width: bodySide,
        height: bodySide
    )
    let shape = squirclePath(in: body)

    // Тень под иконкой: чуть ниже и мягче, как у иконок macOS.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 26,
        color: color(0, 0, 0, 0.45)
    )
    context.setFillColor(color(8, 8, 12, 1))
    context.addPath(shape)
    context.fillPath()
    context.restoreGState()

    // Тело иконки: почти чёрное, как панели приложения.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.setFillColor(color(10, 10, 14))
    context.fill(body)

    // Цветок. Исходник тёмный, поэтому он заполняет сквирл целиком и его
    // собственный фон совпадает с телом иконки — стыка не видно.
    let side = body.width * artInset
    let rect = CGRect(
        x: body.midX - side / 2,
        y: body.midY - side / 2,
        width: side,
        height: side
    )
    context.draw(source, in: rect)

    // Мягкое фиолетовое свечение поверх — глубина без потери контраста.
    if let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(139, 92, 246, 0.16), color(139, 92, 246, 0)] as CFArray,
        locations: [0, 1]
    ) {
        let glowRect = CGRect(
            x: body.midX - body.width * 0.45,
            y: body.midY - body.height * 0.45,
            width: body.width * 0.9,
            height: body.height * 0.9
        )
        context.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
            startRadius: 0,
            endCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
            endRadius: glowRect.width / 2,
            options: []
        )
    }
    context.restoreGState()

    // Тонкий светлый кант по краю — иконка читается на любом фоне.
    context.saveGState()
    context.addPath(shape)
    context.setStrokeColor(color(255, 255, 255, 0.16))
    context.setLineWidth(2)
    context.strokePath()
    context.restoreGState()

    return context.makeImage()
}

func write(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

// MARK: - Точка входа

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <source.png> <master.png>\n".utf8))
    exit(2)
}

guard let loaded = loadImage(at: arguments[1]),
      let cropped = squareCrop(loaded),
      let keyed = makeAlpha(cropped),
      let master = makeMaster(from: keyed) else {
    FileHandle.standardError.write(Data("cannot read the source image\n".utf8))
    exit(1)
}

guard write(master, to: arguments[2]) else {
    FileHandle.standardError.write(Data("cannot write the master image\n".utf8))
    exit(1)
}
print("мастер-иконка: \(arguments[2])")
