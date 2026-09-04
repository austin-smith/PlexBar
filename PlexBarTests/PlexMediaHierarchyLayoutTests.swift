import AppKit
import SwiftUI
import Testing
@testable import PlexBar

@MainActor
@Suite
struct PlexMediaHierarchyLayoutTests {
    @Test func movieDetailsDoNotReserveSpaceForAbsentHistory() {
        let headerRecorder = HierarchyLayoutSizeRecorder()
        let discoveryRecorder = HierarchyLayoutSizeRecorder()
        let sectionsRecorder = HierarchyLayoutSizeRecorder()
        let hostingView = NSHostingView(rootView:
            VStack(alignment: .leading, spacing: 30) {
                HierarchyLayoutSizeProbe(
                    recorder: headerRecorder,
                    intrinsicHeight: 420
                )
                .fixedSize(horizontal: false, vertical: true)

                HierarchyLayoutSizeProbe(
                    recorder: discoveryRecorder,
                    intrinsicHeight: 160
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            .background {
                HierarchyLayoutSizeProbe(
                    recorder: sectionsRecorder,
                    intrinsicHeight: 0
                )
            }
            .frame(width: 900, height: 900, alignment: .topLeading)
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: 900, height: 900)

        hostingView.layoutSubtreeIfNeeded()

        #expect(abs(headerRecorder.size.height - 420) < 0.5)
        #expect(abs(discoveryRecorder.size.height - 160) < 0.5)
        #expect(abs(sectionsRecorder.size.height - 610) < 0.5)
        #expect(abs(headerRecorder.frame.minY - discoveryRecorder.frame.maxY - 30) < 0.5)
    }

    @Test func realShowOverviewDoesNotConsumeTheViewportBeforeSeasons() throws {
        let suiteName = "PlexBarTests.realShowOverviewDoesNotConsumeTheViewportBeforeSeasons"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "studio-show",
          "key": "/library/metadata/studio-show/children",
          "title": "The Studio (2025)",
          "type": "show",
          "year": 2025,
          "duration": 1800000,
          "summary": "A legacy movie studio tries to survive in a rapidly changing world.",
          "studio": "Point Grey Pictures",
          "contentRating": "TV-MA",
          "originallyAvailableAt": "2025-03-26",
          "audienceRating": 7.8,
          "Genre": [{ "tag": "Comedy" }, { "tag": "Drama" }],
          "Role": [
            { "tag": "Seth Rogen", "role": "Matt Remick" },
            { "tag": "Catherine O'Hara", "role": "Patty Leigh" },
            { "tag": "Ike Barinholtz", "role": "Sal Saperstein" },
            { "tag": "Chase Sui Wonders", "role": "Quinn Hackett" },
            { "tag": "Kathryn Hahn", "role": "Maya Mason" },
            { "tag": "Keyla Monterroso Mejia", "role": "Petra" },
            { "tag": "Dewayne Perkins", "role": "Tyler" },
            { "tag": "Nicholas Stoller", "role": "Nicholas Stoller" },
            { "tag": "Bryan Cranston", "role": "Griffin Mill" },
            { "tag": "David Krumholtz", "role": "Mitch Weitz" },
            { "tag": "Zoë Kravitz", "role": "Zoë Kravitz" },
            { "tag": "Dave Franco", "role": "Dave Franco" },
            { "tag": "Matt Belloni", "role": "Matt Belloni" },
            { "tag": "Lisa Gilroy", "role": "Gabby" },
            { "tag": "Rhea Perlman", "role": "Matt's Mom (voice)" },
            { "tag": "Ron Howard", "role": "Ron Howard" },
            { "tag": "Peter Berg", "role": "Peter Berg" },
            { "tag": "Steve Buscemi", "role": "Steve Buscemi" }
          ],
          "Country": [{ "tag": "United States of America" }]
        }
        """#.utf8))
        let settingsStore = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore()
        )
        let overviewRecorder = HierarchyLayoutSizeRecorder()
        let childrenRecorder = HierarchyLayoutSizeRecorder()
        let metadataRecorder = HierarchyLayoutSizeRecorder()

        let hostingView = NSHostingView(rootView:
            NavigationSplitView {
                List {
                    Label("Home", systemImage: "house")
                }
                .navigationSplitViewColumnWidth(228)
            } detail: {
                NavigationStack {
                    ZStack(alignment: .topLeading) {
                        Color(nsColor: .windowBackgroundColor)
                            .ignoresSafeArea()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 30) {
                                PlexMediaOverview(
                                    item: item,
                                    settingsStore: settingsStore,
                                    serverURL: nil,
                                    showsPlaybackControl: true,
                                    isPlaybackEnabled: true,
                                    isPreparingPlayback: false,
                                    preparePlayback: {},
                                    showsAutomaticDownloadControl: false,
                                    prepareAutomaticDownload: {}
                                )
                                .background {
                                    HierarchyLayoutSizeProbe(
                                        recorder: overviewRecorder,
                                        intrinsicHeight: 0
                                    )
                                }

                                Text("Seasons")
                                    .font(.title2.weight(.semibold))
                                    .background {
                                        HierarchyLayoutSizeProbe(
                                            recorder: childrenRecorder,
                                        intrinsicHeight: 0
                                    )
                                }

                                PlexMediaMetadataView(item: item)
                                    .frame(maxWidth: 980, alignment: .leading)
                                    .background {
                                        HierarchyLayoutSizeProbe(
                                            recorder: metadataRecorder,
                                        intrinsicHeight: 0
                                    )
                                }
                            }
                            .frame(maxWidth: 1_100, alignment: .leading)
                            .scenePadding()
                        }
                    }
                    .navigationTitle(item.title)
                    .toolbar {
                        Button("Reload", systemImage: "arrow.clockwise") {}
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(width: 1_400, height: 900, alignment: .topLeading)
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: 1_400, height: 900)

        hostingView.layoutSubtreeIfNeeded()

        #expect(overviewRecorder.size.height >= PlexCinematicHeroMetrics.minimumHeight)
        #expect(overviewRecorder.size.height <= PlexCinematicHeroMetrics.maximumHeight)
        #expect(childrenRecorder.size.height > 15)
        #expect(childrenRecorder.size.height < 60)
        #expect(abs(overviewRecorder.frame.minY - childrenRecorder.frame.maxY - 30) < 0.5)
        #expect(abs(childrenRecorder.frame.minY - metadataRecorder.frame.maxY - 30) < 0.5)
    }
}

@MainActor
private final class HierarchyLayoutSizeRecorder {
    var size = CGSize.zero
    var frame = CGRect.zero
}

private struct HierarchyLayoutSizeProbe: NSViewRepresentable {
    let recorder: HierarchyLayoutSizeRecorder
    let intrinsicHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        HierarchyLayoutProbeNSView(
            recorder: recorder,
            intrinsicHeight: intrinsicHeight
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class HierarchyLayoutProbeNSView: NSView {
    private let recorder: HierarchyLayoutSizeRecorder
    private let intrinsicHeight: CGFloat

    init(recorder: HierarchyLayoutSizeRecorder, intrinsicHeight: CGFloat) {
        self.recorder = recorder
        self.intrinsicHeight = intrinsicHeight
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 100, height: intrinsicHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recorder.size = newSize
        recordFrame()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        recordFrame()
    }

    override func layout() {
        super.layout()
        recordFrame()
    }

    private func recordFrame() {
        recorder.frame = convert(bounds, to: nil)
    }
}
