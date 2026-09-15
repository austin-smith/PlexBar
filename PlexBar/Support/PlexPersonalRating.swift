import Foundation

enum PlexPersonalRating {
    static let starCount = 5
    static let halfStarStep = 0.5
    static let minimumServerValue = 1.0
    static let maximumServerValue = 10.0

    static func stars(fromServerValue serverValue: Double?) -> Double? {
        guard let serverValue,
              serverValue.isFinite,
              (minimumServerValue...maximumServerValue).contains(serverValue) else {
            return nil
        }
        return serverValue / 2
    }

    static func serverValue(fromStars stars: Double) -> Double? {
        guard stars.isFinite,
              (halfStarStep...Double(starCount)).contains(stars) else {
            return nil
        }

        let halfStarSteps = (stars / halfStarStep).rounded(.toNearestOrAwayFromZero)
        return halfStarSteps
    }

    static func stars(at locationX: Double, controlWidth: Double) -> Double? {
        guard locationX.isFinite,
              controlWidth.isFinite,
              controlWidth > 0 else {
            return nil
        }

        let clampedX = min(max(locationX, 0), controlWidth)
        let halfStarSteps = max(1, ceil((clampedX / controlWidth) * maximumServerValue))
        return halfStarSteps * halfStarStep
    }

    static func adjustedServerValue(from currentValue: Double?, by step: Int) -> Double? {
        guard step != 0 else {
            return currentValue
        }

        let currentStep = stars(fromServerValue: currentValue)
            .flatMap(serverValue(fromStars:)) ?? 0
        let adjustedStep = currentStep + Double(step.signum())

        if adjustedStep < minimumServerValue {
            return nil
        }
        return min(adjustedStep, maximumServerValue)
    }

    static func title(forServerValue serverValue: Double?) -> String {
        guard let stars = stars(fromServerValue: serverValue) else {
            return "Rate"
        }
        return title(forStars: stars)
    }

    static func title(forStars stars: Double) -> String {
        let formattedStars = stars.formatted(
            .number.precision(.fractionLength(0...2))
        )
        return "\(formattedStars) \(stars == 1 ? "Star" : "Stars")"
    }

    static func accessibilityValue(forServerValue serverValue: Double?) -> String {
        guard let stars = stars(fromServerValue: serverValue) else {
            return "No rating"
        }
        return title(forStars: stars).lowercased()
    }
}
