import PlexClientKit
import SwiftUI

struct PlexMediaHierarchyBreadcrumbs: View {
    let destinations: [PlexMediaHierarchyDestination]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(destinations) { destination in
                NavigationLink(
                    value: PlexNavigationRoute.media(destination.route)
                ) {
                    Text(destination.title)
                        .lineLimit(1)
                }
                .buttonStyle(.link)
                .accessibilityLabel("Open \(destination.relationship.rawValue) \(destination.title)")

                if destination.id != destinations.last?.id {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct PlexMediaHierarchyNavigationMenu: View {
    let destinations: [PlexMediaHierarchyDestination]

    var body: some View {
        if !destinations.isEmpty {
            Menu("Go to", systemImage: "arrow.up.right") {
                ForEach(destinations) { destination in
                    NavigationLink(
                        value: PlexNavigationRoute.media(destination.route)
                    ) {
                        Label(
                            "\(destination.relationship.rawValue): \(destination.title)",
                            systemImage: destination.relationship.systemImage
                        )
                    }
                }
            }
        }
    }
}

private extension PlexMediaHierarchyDestination.Relationship {
    var systemImage: String {
        switch self {
        case .show:
            "tv"
        case .season:
            "rectangle.stack"
        case .artist:
            "music.mic"
        case .album:
            "square.stack"
        }
    }
}
