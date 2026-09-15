import SwiftUI

struct PlexPlayerHUD<Content: View>: View {
    let title: String
    let systemImage: String
    let dismiss: () -> Void
    private let content: Content

    init(
        title: String,
        systemImage: String,
        dismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.dismiss = dismiss
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 24)

                Button("Close", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .help("Close \(title)")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .opacity(0.7)

            content
        }
        .glassEffect(
            .regular.tint(.black.opacity(0.025)),
            in: .rect(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        .fixedSize(horizontal: true, vertical: true)
        .contentShape(.rect(cornerRadius: 24))
        .onTapGesture { }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
