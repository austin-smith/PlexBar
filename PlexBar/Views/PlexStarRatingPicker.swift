import SwiftUI

struct PlexStarRatingPicker: View {
    let serverValue: Double?
    let isDisabled: Bool
    let onSelect: (Double) -> Void

    @ScaledMetric(relativeTo: .title3) private var starSize = 20.0
    @ScaledMetric(relativeTo: .title3) private var starSpacing = 3.0
    @State private var previewStars: Double?

    private var controlWidth: Double {
        (starSize * Double(PlexPersonalRating.starCount))
            + (starSpacing * Double(PlexPersonalRating.starCount - 1))
    }

    private var selectedStars: Double {
        PlexPersonalRating.stars(fromServerValue: serverValue) ?? 0
    }

    private var displayedStars: Double {
        previewStars ?? selectedStars
    }

    var body: some View {
        HStack(spacing: starSpacing) {
            ForEach(0..<PlexPersonalRating.starCount, id: \.self) { index in
                star(at: index)
            }
        }
        .frame(width: controlWidth, height: starSize)
        .contentShape(.rect)
        .onContinuousHover(coordinateSpace: .local, perform: updatePreview)
        .gesture(
            SpatialTapGesture(coordinateSpace: .local)
                .onEnded(selectRating)
        )
        .focusable(!isDisabled)
        .onKeyPress(.leftArrow) {
            adjustRating(by: -1)
        }
        .onKeyPress(.downArrow) {
            adjustRating(by: -1)
        }
        .onKeyPress(.rightArrow) {
            adjustRating(by: 1)
        }
        .onKeyPress(.upArrow) {
            adjustRating(by: 1)
        }
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your Rating")
        .accessibilityValue(PlexPersonalRating.accessibilityValue(forServerValue: serverValue))
        .accessibilityHint("Adjusts in half-star steps")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                submitAdjustment(by: 1)
            case .decrement:
                submitAdjustment(by: -1)
            @unknown default:
                break
            }
        }
        .help(PlexPersonalRating.accessibilityValue(forServerValue: serverValue).capitalized)
    }

    private func star(at index: Int) -> some View {
        let fill = min(max(displayedStars - Double(index), 0), 1)

        return Image(systemName: "star")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .overlay(alignment: .leading) {
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tint)
                    .frame(width: starSize, height: starSize)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: starSize * fill)
                    }
            }
            .frame(width: starSize, height: starSize)
    }

    private func updatePreview(_ phase: HoverPhase) {
        guard !isDisabled else {
            previewStars = nil
            return
        }

        switch phase {
        case let .active(location):
            previewStars = PlexPersonalRating.stars(
                at: location.x,
                controlWidth: controlWidth
            )
        case .ended:
            previewStars = nil
        }
    }

    private func selectRating(_ value: SpatialTapGesture.Value) {
        guard !isDisabled,
              let stars = PlexPersonalRating.stars(
                  at: value.location.x,
                  controlWidth: controlWidth
              ),
              let selectedValue = PlexPersonalRating.serverValue(fromStars: stars) else {
            return
        }
        onSelect(selectedValue)
    }

    private func adjustRating(by step: Int) -> KeyPress.Result {
        guard !isDisabled else {
            return .ignored
        }
        submitAdjustment(by: step)
        return .handled
    }

    private func submitAdjustment(by step: Int) {
        guard !isDisabled,
              let adjustedValue = PlexPersonalRating.adjustedServerValue(
                  from: serverValue,
                  by: step
              ) else {
            return
        }
        onSelect(adjustedValue)
    }
}
