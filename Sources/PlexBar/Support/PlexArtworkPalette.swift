import CoreGraphics
import SwiftUI

struct PlexPaletteColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    var brightness: Double {
        max(red, green, blue)
    }

    var saturation: Double {
        let maximum = brightness
        guard maximum > 0 else {
            return 0
        }

        let minimum = min(red, green, blue)
        return (maximum - minimum) / maximum
    }

    func distance(to other: PlexPaletteColor) -> Double {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        return sqrt(redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta)
    }

    func blended(with other: PlexPaletteColor, ratio: Double) -> PlexPaletteColor {
        let clampedRatio = ratio.clamped(to: 0...1)
        return PlexPaletteColor(
            red: red + (other.red - red) * clampedRatio,
            green: green + (other.green - green) * clampedRatio,
            blue: blue + (other.blue - blue) * clampedRatio
        )
    }

    func adjusted(saturation multiplier: Double, brightness offset: Double) -> PlexPaletteColor {
        let hsv = rgbToHSV()
        let adjustedBrightness = (hsv.value + offset).clamped(to: 0.18...0.44)
        if hsv.saturation < Self.neutralSaturationThreshold {
            return PlexPaletteColor(
                red: adjustedBrightness,
                green: adjustedBrightness,
                blue: adjustedBrightness
            )
        }

        let adjustedSaturation = (hsv.saturation * multiplier).clamped(to: 0.24...0.82)
        return Self(hue: hsv.hue, saturation: adjustedSaturation, brightness: adjustedBrightness)
    }

    func normalizedForMeshBackground() -> PlexPaletteColor {
        let hsv = rgbToHSV()
        let normalizedBrightness = (0.12 + hsv.value * 0.34).clamped(to: 0.18...0.42)
        if hsv.saturation < Self.neutralSaturationThreshold {
            return PlexPaletteColor(
                red: normalizedBrightness,
                green: normalizedBrightness,
                blue: normalizedBrightness
            )
        }

        let normalizedSaturation = max(hsv.saturation * 1.18, 0.28).clamped(to: 0.28...0.84)
        return Self(hue: hsv.hue, saturation: normalizedSaturation, brightness: normalizedBrightness)
    }

    private static let neutralSaturationThreshold = 0.05

    private func rgbToHSV() -> (hue: Double, saturation: Double, value: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = ((blue - red) / delta) + 2
        } else {
            hue = ((red - green) / delta) + 4
        }

        let normalizedHue = ((hue / 6).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let saturation = maximum == 0 ? 0 : delta / maximum
        return (normalizedHue, saturation, maximum)
    }

    private init(hue: Double, saturation: Double, brightness: Double) {
        if saturation == 0 {
            self.init(red: brightness, green: brightness, blue: brightness)
            return
        }

        let scaledHue = ((hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)) * 6
        let index = Int(floor(scaledHue))
        let fraction = scaledHue - Double(index)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))

        switch index {
        case 0:
            self.init(red: brightness, green: t, blue: p)
        case 1:
            self.init(red: q, green: brightness, blue: p)
        case 2:
            self.init(red: p, green: brightness, blue: t)
        case 3:
            self.init(red: p, green: q, blue: brightness)
        case 4:
            self.init(red: t, green: p, blue: brightness)
        default:
            self.init(red: brightness, green: p, blue: q)
        }
    }
}

struct PlexArtworkPalette: Equatable, Sendable {
    let colors: [PlexPaletteColor]

    init(colors: [PlexPaletteColor]) {
        precondition(colors.count == 4, "PlexArtworkPalette expects exactly four colors.")
        self.colors = colors
    }

    var swiftUIColors: [Color] {
        colors.map(\.swiftUIColor)
    }
}

struct PlexArtworkPaletteExtractor: Sendable {
    private struct ColorBucket {
        var redTotal = 0.0
        var greenTotal = 0.0
        var blueTotal = 0.0
        var count = 0

        mutating func append(red: Double, green: Double, blue: Double) {
            redTotal += red
            greenTotal += green
            blueTotal += blue
            count += 1
        }

        var averageColor: PlexPaletteColor {
            let sampleCount = max(Double(count), 1)
            return PlexPaletteColor(
                red: redTotal / sampleCount,
                green: greenTotal / sampleCount,
                blue: blueTotal / sampleCount
            )
        }
    }

    private struct Candidate {
        let color: PlexPaletteColor
        let score: Double
    }

    private let sampleSize = 24

    func extract(from image: CGImage) -> PlexArtworkPalette? {
        guard let samples = sampledPixels(from: image) else {
            return nil
        }

        var buckets: [Int: ColorBucket] = [:]
        var overall = ColorBucket()

        for sample in samples where sample.alpha > 0.15 {
            let brightness = max(sample.red, sample.green, sample.blue)
            guard brightness > 0.05, brightness < 0.98 else {
                continue
            }

            overall.append(red: sample.red, green: sample.green, blue: sample.blue)

            let key = quantizedKey(red: sample.red, green: sample.green, blue: sample.blue)
            buckets[key, default: ColorBucket()].append(
                red: sample.red,
                green: sample.green,
                blue: sample.blue
            )
        }

        let candidates = buckets.values.compactMap { bucket -> Candidate? in
            guard bucket.count > 0 else {
                return nil
            }

            let normalizedColor = bucket.averageColor.normalizedForMeshBackground()
            let prominence = Double(bucket.count)
            let saturationWeight = 0.3 + normalizedColor.saturation * 0.9
            let brightnessWeight = 1.0 - min(abs(normalizedColor.brightness - 0.30) / 0.30, 1.0) * 0.45
            return Candidate(
                color: normalizedColor,
                score: prominence * saturationWeight * brightnessWeight
            )
        }
        .sorted { $0.score > $1.score }

        var selected: [PlexPaletteColor] = []

        for candidate in candidates {
            guard selected.allSatisfy({ $0.distance(to: candidate.color) > 0.16 }) else {
                continue
            }

            selected.append(candidate.color)
            if selected.count == 4 {
                break
            }
        }

        if selected.isEmpty, overall.count > 0 {
            selected.append(overall.averageColor.normalizedForMeshBackground())
        }

        guard !selected.isEmpty else {
            return nil
        }

        return PlexArtworkPalette(colors: expandedColors(from: selected))
    }

    private func expandedColors(from colors: [PlexPaletteColor]) -> [PlexPaletteColor] {
        if colors.count >= 4 {
            return Array(colors.prefix(4))
        }

        if colors.count == 1 {
            let base = colors[0]
            return [
                base,
                base.adjusted(saturation: 1.12, brightness: 0.05),
                base.adjusted(saturation: 0.92, brightness: -0.03),
                base.adjusted(saturation: 1.20, brightness: 0.01),
            ]
        }

        if colors.count == 2 {
            let first = colors[0]
            let second = colors[1]
            return [
                first,
                second,
                first.blended(with: second, ratio: 0.5).adjusted(saturation: 1.08, brightness: 0.02),
                first.adjusted(saturation: 0.95, brightness: -0.02),
            ]
        }

        let first = colors[0]
        let second = colors[1]
        let third = colors[2]
        return [
            first,
            second,
            third,
            first.blended(with: third, ratio: 0.5).adjusted(saturation: 1.06, brightness: 0.01),
        ]
    }

    private func quantizedKey(red: Double, green: Double, blue: Double) -> Int {
        let redBin = min(Int(red * 5), 5)
        let greenBin = min(Int(green * 5), 5)
        let blueBin = min(Int(blue * 5), 5)
        return redBin << 8 | greenBin << 4 | blueBin
    }

    private func sampledPixels(from image: CGImage) -> [(red: Double, green: Double, blue: Double, alpha: Double)]? {
        let width = sampleSize
        let height = sampleSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: buffer.count, by: bytesPerPixel).map { offset in
            let red = Double(buffer[offset]) / 255
            let green = Double(buffer[offset + 1]) / 255
            let blue = Double(buffer[offset + 2]) / 255
            let alpha = Double(buffer[offset + 3]) / 255
            return (red, green, blue, alpha)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
