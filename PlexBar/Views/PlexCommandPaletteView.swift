import PlexClientKit
import PlexModels
import SwiftUI

struct PlexCommandPaletteView: View {
    @Bindable var store: PlexCommandPaletteStore
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let maximumResultsHeight: CGFloat
    let isComposingText: () -> Bool
    let dismiss: () -> Void
    let execute: (PlexPaletteResult) -> Void
    let play: (PlexPaletteResult) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var isSearchFocused: Bool
    @State private var resultsHeight: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
            Divider()
            footer
        }
        .frame(maxWidth: 640)
        .background {
            Button(action: { isSearchFocused = true }) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityHidden(true)
        }
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search Library and Commands")
        .accessibilityAddTraits(.isModal)
        .onExitCommand {
            guard !isComposingText() else { return }
            dismiss()
        }
        .onAppear {
            // SwiftUI must attach the native field before it can become first responder.
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search your library or run a command…", text: $store.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .accessibilityLabel("Search library or commands")
                .accessibilityHint("Arrow keys select a result. Return opens it. Command Return plays playable content.")
                .onSubmit {
                    guard !isComposingText(), !store.isPreparingPlayback,
                          let result = store.selectedResult else { return }
                    execute(result)
                }
                .onKeyPress(.downArrow, phases: [.down, .repeat]) { moveSelection(by: 1, modifiers: $0.modifiers) }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) { moveSelection(by: -1, modifiers: $0.modifiers) }
            if !store.query.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    store.query = ""
                    isSearchFocused = true
                }
                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Button(action: dismiss) {
                Text("esc").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.quaternary, in: .rect(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Search")
        }
        .padding(18)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    searchStatus
                    ForEach(store.results) { result in
                        if startsGroup(result) {
                            HStack {
                                Text(result.group).font(.caption.weight(.semibold))
                                    .accessibilityAddTraits(.isHeader)
                                Spacer()
                                if result.group == "Recently Opened" {
                                    Button("Clear", action: store.clearRecents).buttonStyle(.plain)
                                        .accessibilityLabel("Clear Recently Opened")
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 5)
                        }
                        PlexPaletteResultRow(
                            result: result, query: store.searchQuery, selected: store.selectedID == result.id,
                            settingsStore: settingsStore, serverURL: serverURL,
                            execute: { store.select(result.id); execute(result) }
                        )
                        .disabled(store.isPreparingPlayback)
                        .id(result.id)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultsHeight = $0 }
            }
            .frame(height: min(resultsHeight, maximumResultsHeight))
            .onChange(of: store.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .onChange(of: store.query) {
                if let first = store.results.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private var searchStatus: some View {
        if store.isPreparingPlayback {
            statusRow("Preparing playback…", loading: true)
        } else if let error = store.actionError {
            statusRow("Couldn’t Start Playback", detail: error)
        }
        if !store.canSearch {
            statusRow("Library search unavailable", detail: "Connect to a Plex server to search. Downloads and commands remain available.")
        } else if store.isSearching {
            statusRow("Searching all libraries…", loading: true)
        } else if let error = store.searchError {
            VStack(alignment: .leading, spacing: 8) {
                statusRow("Couldn’t Search Libraries", detail: error)
                Button("Try Again", action: store.retry).padding(.horizontal, 12)
            }
        } else if !store.searchQuery.isEmpty, !store.hasMatchingResults {
            statusRow("No results for “\(store.searchQuery)”", detail: "Try another title or command.")
        }
    }

    private func statusRow(_ title: String, detail: String? = nil, loading: Bool = false) -> some View {
        HStack(spacing: 10) {
            if loading { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.medium))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("Navigate", systemImage: "arrow.up.arrow.down")
            Spacer(minLength: 0)
            if let result = store.selectedResult {
                if result.canPlay {
                    Button { play(result) } label: { Text("⌘↵ \(result.playTitle)") }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(store.isPreparingPlayback)
                }
                Text(result.isCommand ? "↵ Run" : "↵ Open")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func startsGroup(_ result: PlexPaletteResult) -> Bool {
        guard let index = store.results.firstIndex(where: { $0.id == result.id }) else { return false }
        return index == 0 || store.results[index - 1].group != result.group
    }

    private func moveSelection(by offset: Int, modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty,
              !isComposingText(), !store.isPreparingPlayback else { return .ignored }
        store.moveSelection(by: offset)
        if voiceOverEnabled, let result = store.selectedResult {
            AccessibilityNotification.Announcement([result.title, result.subtitle].compactMap { $0 }.joined(separator: ", ")).post()
        }
        return .handled
    }
}

private extension PlexPaletteResult {
    var isCommand: Bool { if case .command = content { true } else { false } }
}

private struct PlexPaletteResultRow: View {
    let result: PlexPaletteResult
    let query: String
    let selected: Bool
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    let execute: () -> Void
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: execute) {
            HStack(spacing: 12) {
                artwork.frame(width: 48, height: result.isCommand ? 28 : 48).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(highlightedTitle).font(.body.weight(selected ? .medium : .regular)).lineLimit(1)
                    if let subtitle = result.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if case .command(let command) = result.content, let shortcut = command.shortcut {
                    Text(shortcut).font(.caption.monospaced()).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Image(systemName: "return").font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor).opacity(selected ? 1 : 0).accessibilityHidden(true)
            }
            .padding(.horizontal, 10).padding(.vertical, 8).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!result.isEnabled)
        .opacity(result.isEnabled ? 1 : 0.55)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(hovered ? 0.05 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.accentColor.opacity(selected && contrast == .increased ? 1 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(result.isCommand ? "Run command" : "Open details")
    }

    @ViewBuilder
    private var artwork: some View {
        switch result.content {
        case .command(let command):
            Image(systemName: command.systemImage).font(.body).foregroundStyle(.secondary)
        case .allResults:
            Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
        case .media(let item, let download):
            if let download {
                PlexDownloadedArtwork(url: download.package.artworkURL, placeholderSystemImage: "film", width: 32, height: 48)
            } else {
                let artwork = PlexMediaArtworkPresentation(item: item)
                let width: CGFloat = artwork.shape == .poster ? 32 : 44
                let height: CGFloat = artwork.shape == .landscape ? 28 : 48
                PlexArtworkView(
                    primaryImageURL: serverURL.flatMap { PlexURLBuilder.mediaURL(serverURL: $0, path: artwork.path) },
                    fallbackImageURL: nil, token: settingsStore.trimmedServerToken,
                    clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                    placeholderSymbol: item.type == "track" || item.type == "album" ? "music.note" : "film",
                    width: width, height: artwork.shape == .square ? width : height, cornerRadius: 4
                )
            }
        }
    }

    private var highlightedTitle: AttributedString {
        var title = AttributedString(result.title)
        for token in query.split(whereSeparator: \.isWhitespace) {
            if let range = title.range(of: String(token), options: [.caseInsensitive, .diacriticInsensitive]) {
                title[range].font = .body.weight(.semibold)
            }
        }
        return title
    }
}
