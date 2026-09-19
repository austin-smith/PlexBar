import AppKit
import SwiftUI

/// Native slider input and accessibility with a quiet, knobless volume track.
struct PlexPlayerVolumeSlider: NSViewRepresentable {
    @Binding var value: Double

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = PlexPlayerVolumeSliderCell()
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.controlSize = .small
        slider.numberOfTickMarks = 17
        slider.allowsTickMarkValuesOnly = false
        slider.trackFillColor = .white
        slider.tintProminence = .primary
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changeVolume(_:))
        slider.setAccessibilityLabel("Volume")
        updateNSView(slider, context: context)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        if slider.doubleValue != value { slider.doubleValue = value }
        slider.setAccessibilityValueDescription("\(Int(value * 100)) percent")
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) { self.value = value }

        @objc func changeVolume(_ slider: NSSlider) {
            value.wrappedValue = slider.doubleValue
        }
    }
}

final class PlexPlayerVolumeSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()

        let fraction = (doubleValue - minValue) / (maxValue - minValue)
        let filled = NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()

        let tickY = flipped ? track.maxY + 4 : track.minY - 6
        NSColor.white.withAlphaComponent(0.2).setFill()
        for index in 0..<numberOfTickMarks {
            let x = track.minX + 1 + (track.width - 2) * Double(index) / Double(numberOfTickMarks - 1)
            NSBezierPath(ovalIn: NSRect(x: x - 1, y: tickY, width: 2, height: 2)).fill()
        }
    }

    override func drawTickMarks() {}
    override func drawKnob(_ knobRect: NSRect) {}
    override func drawKnob() {}
}
