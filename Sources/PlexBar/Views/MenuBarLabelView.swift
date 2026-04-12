import SwiftUI

struct MenuBarLabelView: View {
    let streamCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: streamCount > 0 ? "play.rectangle.fill" : "play.rectangle")

            if streamCount > 0 {
                Text("\(streamCount)")
                    .monospacedDigit()
            }
        }
    }
}
