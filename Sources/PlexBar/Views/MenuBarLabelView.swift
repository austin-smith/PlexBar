import SwiftUI

struct MenuBarLabelView: View {
    let streamCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "popcorn.fill")

            if streamCount > 0 {
                Text("\(streamCount)")
                    .monospacedDigit()
            }
        }
    }
}
