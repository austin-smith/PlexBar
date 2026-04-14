import SwiftUI

struct MenuBarLabelView: View {
    let streamCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 16, height: 16)

            if streamCount > 0 {
                Text("\(streamCount)")
                    .monospacedDigit()
            }
        }
    }
}
