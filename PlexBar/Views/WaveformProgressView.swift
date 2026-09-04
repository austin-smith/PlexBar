import SwiftUI

struct WaveformProgressView: View {
    let levels: [Double]
    let progress: Double
    let isPaused: Bool

    private let height: CGFloat = 30

    var body: some View {
        let scale = WaveformScale(levels: levels)

        Canvas { context, size in
            let waveform = waveformPath(size: size, scale: scale)
            drawWaveform(waveform, in: &context, size: size)
            drawBaseline(in: &context, size: size)
        }
        .frame(height: height)
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(Int((clampedProgress * 100).rounded())) percent")
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private func drawBaseline(in context: inout GraphicsContext, size: CGSize) {
        let centerY = size.height / 2
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: centerY))
        baseline.addLine(to: CGPoint(x: size.width, y: centerY))
        context.stroke(baseline, with: .color(.white.opacity(isPaused ? 0.12 : 0.18)), lineWidth: 1)
    }

    private func drawWaveform(_ path: Path, in context: inout GraphicsContext, size: CGSize) {
        let baseOpacity = isPaused ? 0.12 : 0.18
        let playedColor = Color.orange.opacity(isPaused ? 0.22 : 0.34)

        context.fill(path, with: .color(.white.opacity(baseOpacity)))

        var playedContext = context
        playedContext.clip(to: Path(CGRect(
            x: 0,
            y: 0,
            width: size.width * CGFloat(clampedProgress),
            height: size.height
        )))
        playedContext.fill(path, with: .color(playedColor))
    }

    private func waveformPath(size: CGSize, scale: WaveformScale) -> Path {
        let centerY = size.height / 2
        let maxAmplitude = (size.height - 2) / 2
        let amplitudes = smoothedAmplitudes(scale: scale, maxAmplitude: maxAmplitude)
        let stepWidth = amplitudes.count > 1 ? size.width / CGFloat(amplitudes.count - 1) : size.width
        var path = Path()

        path.move(to: CGPoint(x: 0, y: centerY))

        for (index, amplitude) in amplitudes.enumerated() {
            let x = CGFloat(index) * stepWidth
            path.addLine(to: CGPoint(x: x, y: centerY - amplitude))
        }

        for (index, amplitude) in amplitudes.enumerated().reversed() {
            let x = CGFloat(index) * stepWidth
            path.addLine(to: CGPoint(x: x, y: centerY + amplitude))
        }

        path.closeSubpath()
        return path
    }

    private func smoothedAmplitudes(scale: WaveformScale, maxAmplitude: CGFloat) -> [CGFloat] {
        let rawAmplitudes = levels.map { scale.normalizedAmplitude(for: $0) * maxAmplitude }

        guard rawAmplitudes.count > 2 else {
            return rawAmplitudes
        }

        return rawAmplitudes.indices.map { index in
            let previous = rawAmplitudes[max(index - 1, rawAmplitudes.startIndex)]
            let current = rawAmplitudes[index]
            let next = rawAmplitudes[min(index + 1, rawAmplitudes.index(before: rawAmplitudes.endIndex))]
            return previous * 0.22 + current * 0.56 + next * 0.22
        }
    }
}

private struct WaveformScale {
    private let lowerBound: Double
    private let upperBound: Double

    init(levels: [Double]) {
        let sortedLevels = levels.sorted()

        guard let quietLevel = sortedLevels.percentile(0.08),
              let loudLevel = sortedLevels.percentile(0.92) else {
            lowerBound = -42
            upperBound = -14
            return
        }

        let minimumSpan = 7.0
        let midpoint = (quietLevel + loudLevel) / 2
        let span = max(loudLevel - quietLevel, minimumSpan)
        lowerBound = midpoint - span / 2
        upperBound = midpoint + span / 2
    }

    func normalizedAmplitude(for decibels: Double) -> CGFloat {
        let clampedLevel = min(max(decibels, lowerBound), upperBound)
        let linearLevel = (clampedLevel - lowerBound) / (upperBound - lowerBound)
        return CGFloat(0.05 + pow(linearLevel, 1.22) * 0.95)
    }
}

private extension Array where Element == Double {
    func percentile(_ percentile: Double) -> Double? {
        guard !isEmpty else {
            return nil
        }

        let clampedPercentile = Swift.min(Swift.max(percentile, 0), 1)
        let index = Int((Double(count - 1) * clampedPercentile).rounded())
        return self[index]
    }
}
