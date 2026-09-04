import SwiftUI

struct PlexExternalRatingsView: View {
    let ratings: [PlexExternalRatingPresentation]

    init(item: PlexMediaItem) {
        ratings = PlexExternalRatingsPresentation(item: item).ratings
    }

    var body: some View {
        if !ratings.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) {
                    ratingViews
                }

                VStack(alignment: .leading, spacing: 8) {
                    ratingViews
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var ratingViews: some View {
        ForEach(ratings) { rating in
            PlexExternalRatingView(rating: rating)
        }
    }
}

private struct PlexExternalRatingView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let rating: PlexExternalRatingPresentation

    var body: some View {
        if let destinationURL = rating.destinationURL {
            Link(destination: destinationURL) {
                ratingContent
            }
            .buttonStyle(.plain)
            .help("Open on IMDb")
            .accessibilityLabel(rating.accessibilityLabel)
            .accessibilityHint("Opens the IMDb title page in your default browser")
        } else {
            ratingContent
                .accessibilityLabel(rating.accessibilityLabel)
        }
    }

    private var ratingContent: some View {
        HStack(spacing: 7) {
            ratingMark
                .accessibilityHidden(true)

            Text(rating.displayValue)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.numericText())
                .animation(
                    PlexMotion.contentReplacementAnimation(
                        reduceMotion: accessibilityReduceMotion
                    ),
                    value: rating.displayValue
                )
                .accessibilityHidden(true)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder
    private var ratingMark: some View {
        switch rating.source {
        case .imdb:
            PlexIMDbMark()
        case .rottenTomatoes:
            PlexTomatometerMark(isFresh: rating.isFresh == true)
        }
    }
}

private struct PlexIMDbMark: View {
    @ScaledMetric(relativeTo: .headline) private var width = 35.0
    @ScaledMetric(relativeTo: .headline) private var height = 18.0
    @ScaledMetric(relativeTo: .headline) private var textSize = 9.5

    var body: some View {
        Text("IMDb")
            .font(.system(size: textSize, weight: .black, design: .default))
            .foregroundStyle(.black)
            .frame(width: width, height: height)
            .background(Color(red: 0.96, green: 0.78, blue: 0.12))
            .clipShape(.rect(cornerRadius: height * 0.14))
    }
}

private struct PlexTomatometerMark: View {
    let isFresh: Bool
    @ScaledMetric(relativeTo: .headline) private var size = 22.0

    var body: some View {
        Group {
            if isFresh {
                PlexFreshTomatoMark()
            } else {
                PlexRottenTomatoMark()
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PlexFreshTomatoMark: View {
    var body: some View {
        ZStack {
            PlexTomatoBodyShape()
                .fill(Color(red: 0.91, green: 0.13, blue: 0.13))
                .overlay {
                    PlexTomatoBodyShape()
                        .stroke(Color.white.opacity(0.82), lineWidth: 1.15)
                }

            Circle()
                .fill(.white.opacity(0.42))
                .frame(width: 4.2, height: 3.1)
                .offset(x: -4.5, y: -2.8)

            PlexTomatoLeavesShape()
                .fill(Color(red: 0.18, green: 0.57, blue: 0.20))
                .frame(width: 13, height: 8)
                .offset(y: -8)
        }
        .padding(.top, 2)
    }
}

private struct PlexRottenTomatoMark: View {
    var body: some View {
        ZStack {
            PlexRottenSplatShape()
                .fill(Color(red: 0.36, green: 0.69, blue: 0.20))
                .overlay {
                    PlexRottenSplatShape()
                        .stroke(Color.white.opacity(0.82), lineWidth: 1.1)
                }

            Circle()
                .fill(.white.opacity(0.35))
                .frame(width: 3.5, height: 2.8)
                .offset(x: -3.8, y: -3.2)
        }
        .padding(1)
    }
}

private struct PlexTomatoBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.04),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.10),
            control2: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.10)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.28),
            control2: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY)
        )
        return path
    }
}

private struct PlexTomatoLeavesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5 - .pi / 2
            let radius = index.isMultiple(of: 2) ? rect.width * 0.49 : rect.width * 0.18
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius * 0.55
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct PlexRottenSplatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<20 {
            let angle = Double(index) * .pi / 10 - .pi / 2
            let scale: CGFloat = index.isMultiple(of: 2) ? 0.49 : 0.34
            let point = CGPoint(
                x: center.x + cos(angle) * rect.width * scale,
                y: center.y + sin(angle) * rect.height * scale
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
