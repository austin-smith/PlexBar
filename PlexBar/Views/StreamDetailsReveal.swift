import SwiftUI

struct StreamDetailsReveal<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        StreamDetailsRevealLayout(progress: isExpanded ? 1 : 0) {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .clipped()
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
    }
}

// Animate the measured height itself so the menu panel follows each frame,
// rather than resizing to the final height before the details finish collapsing.
@Animatable
private struct StreamDetailsRevealLayout: Layout {
    var progress: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: size.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}
