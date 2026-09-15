import AppKit
import SwiftUI
import Testing
@testable import PlexBar

@MainActor @Observable
private final class RevealTestState {
    var expanded = true
    var heights: [CGFloat] = []
    @ObservationIgnored private let traceStart = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private(set) var trace: [String] = []

    func record(_ event: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - traceStart
        trace.append(String(format: "%.6fs %@", elapsed, event))
    }
}

private struct RevealHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Reproduce the menu's measured, height-capped scroll container. A conditional
// details view reports only the final height here and fails the motion checks.
private struct RevealTestMenu: View {
    let state: RevealTestState
    let cardCount: Int
    let maximumHeight: CGFloat
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<cardCount, id: \.self) { index in
                    VStack(spacing: 0) {
                        Color.blue.frame(height: 132)
                        StreamDetailsReveal(isExpanded: index == 0 && state.expanded) {
                            Color.red.frame(height: 168)
                        }
                    }
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: RevealHeightPreference.self, value: proxy.size.height)
                }
            }
        }
        .frame(width: 388, height: min(max(height, 132), maximumHeight))
        .onPreferenceChange(RevealHeightPreference.self) { size in
            state.record("content expanded=\(state.expanded) previous=\(height) measured=\(size)")
            guard abs(height - size) > 0.5 else { return }
            height = size
            state.heights.append(size)
        }
    }
}

@MainActor @Suite(.serialized)
struct StreamDetailsRevealTests {
    @Test(arguments: [CGFloat(220), CGFloat(760)])
    func panelFollowsExpansionAndCollapse(maximumHeight: CGFloat) async throws {
        try await verifyReveal(cardCount: 1, maximumHeight: maximumHeight, animated: true)
    }

    @Test
    func withoutAnimationChangesHeightImmediately() async throws {
        try await verifyReveal(cardCount: 1, maximumHeight: 760, animated: false)
    }

    private func verifyReveal(cardCount: Int, maximumHeight: CGFloat, animated: Bool) async throws {
        let state = RevealTestState()
        defer {
            print("REVEAL TRACE animated=\(animated) cards=\(cardCount) maximumHeight=\(maximumHeight)\n"
                + state.trace.joined(separator: "\n"))
        }
        let host = NSHostingView(rootView: RevealTestMenu(
            state: state, cardCount: cardCount, maximumHeight: maximumHeight
        ))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 388, height: 760),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        try await Task.sleep(for: .milliseconds(200))

        let collapsedHeight = CGFloat(cardCount * 132 + (cardCount - 1) * 12)
        let expandedHeight = collapsedHeight + 168
        #expect(abs((state.heights.last ?? 0) - expandedHeight) < 1)

        for expanded in [false, true] {
            state.heights = []
            state.record("toggle from=\(state.expanded) to=\(expanded)")
            withAnimation(animated ? .easeInOut(duration: 0.3) : nil) {
                state.expanded = expanded
            }
            var panelHeights: [CGFloat] = []
            for _ in 0..<25 {
                host.layoutSubtreeIfNeeded()
                let panelHeight = host.fittingSize.height
                panelHeights.append(panelHeight)
                state.record("panel expanded=\(state.expanded) measured=\(panelHeight)")
                try await Task.sleep(for: .milliseconds(20))
            }

            let target = expanded ? expandedHeight : collapsedHeight
            state.record("expected content=\(target) panel=\(min(target, maximumHeight)) contentSamples=\(state.heights)")
            #expect(abs((state.heights.last ?? 0) - target) < 1)
            #expect(abs(host.fittingSize.height - min(target, maximumHeight)) < 1)
            if animated {
                #expect(state.heights.contains { $0 > collapsedHeight + 1 && $0 < expandedHeight - 1 })
                if collapsedHeight < maximumHeight {
                    #expect(panelHeights.contains {
                        $0 > collapsedHeight + 1 && $0 < min(expandedHeight, maximumHeight) - 1
                    })
                }
            } else {
                #expect(state.heights.allSatisfy { abs($0 - target) < 1 })
            }
        }
    }
}
