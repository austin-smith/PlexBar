import SwiftUI

struct TVNavigationDestination: View {
    let route: TVNavigationRoute

    var body: some View {
        switch route {
        case .media(let item): TVMediaDetailView(seedItem: item)
        case .person(let route): TVPersonDetailView(route: route)
        }
    }
}
