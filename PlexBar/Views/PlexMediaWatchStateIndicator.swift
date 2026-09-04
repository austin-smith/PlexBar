import SwiftUI

struct PlexMediaWatchStateIndicator: View {
    enum Scale {
        case compact
        case standard

        var badgeSize: CGFloat {
            switch self {
            case .compact: 14
            case .standard: 18
            }
        }

        var symbolSize: CGFloat {
            switch self {
            case .compact: 7
            case .standard: 9
            }
        }

        var edgeInset: CGFloat {
            switch self {
            case .compact: 4
            case .standard: 6
            }
        }

    }

    let isWatched: Bool
    var scale: Scale = .standard

    var body: some View {
        Color.clear
            .overlay(alignment: .topTrailing) {
                if isWatched {
                    watchedBadge
                        .padding(scale.edgeInset)
                }
            }
            .accessibilityHidden(true)
    }

    private var watchedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: scale.symbolSize, weight: .semibold))
            .foregroundStyle(.black.opacity(0.88))
            .frame(width: scale.badgeSize, height: scale.badgeSize)
            .background(.white.opacity(0.96), in: Circle())
            .overlay {
                Circle()
                    .stroke(.black.opacity(0.72), lineWidth: 1)
            }
    }

}

extension View {
    func plexWatchedIndicator(
        isWatched: Bool,
        scale: PlexMediaWatchStateIndicator.Scale = .standard
    ) -> some View {
        overlay {
            PlexMediaWatchStateIndicator(isWatched: isWatched, scale: scale)
        }
    }
}
