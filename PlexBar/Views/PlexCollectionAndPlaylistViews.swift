import PlexClientKit
import PlexModels
import SwiftUI

struct PlexCollectionsView: View {
    let libraries: [PlexLibrary]
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator

    var body: some View {
        List {
            ForEach(libraries) { library in
                PlexCollectionSection(
                    library: library,
                    browserStore: browserStore,
                    settingsStore: settingsStore,
                    connectionStore: connectionStore,
                    playerCoordinator: playerCoordinator
                )
            }
        }
        .listStyle(.inset)
        .navigationTitle("Collections")
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Refresh Collections",
                isEnabled: !libraries.isEmpty,
                perform: refresh
            )
        )
        .task {
            await browserStore.loadLibraryProviderCapabilities()
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh Collections", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(libraries.isEmpty)
            }
        }
    }

    private func refresh() {
        for library in libraries {
            Task {
                await browserStore.loadCollections(in: library, forceRefresh: true)
            }
        }
    }
}

private struct PlexCollectionSection: View {
    let library: PlexLibrary
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @State private var presentedEditor: CollectionEditorRequest?
    @State private var deletionCandidate: PlexMediaItem?
    @State private var mutationErrorMessage: String?

    var body: some View {
        Section {
            if browserStore.isLoadingCollections(in: library), collections.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .accessibilityLabel("Loading collections in \(library.title)")
            } else if let errorMessage = browserStore.collectionsErrorMessage(in: library),
                      collections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Try Again", action: refresh)
                }
                .padding(.vertical, 8)
            } else if collections.isEmpty {
                Text("No Collections")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(collections) { collection in
                    NavigationLink(value: PlexNavigationRoute.media(PlexMediaRoute(item: collection))) {
                        PlexMediaChildRow(
                            item: collection,
                            settingsStore: settingsStore,
                            serverURL: connectionStore.resolvedServerURL
                        )
                    }
                    .contextMenu {
                        if browserStore.supportsCollectionManagement {
                            Button("Rename Collection", systemImage: "pencil") {
                                presentedEditor = .rename(collection)
                            }
                            Button("Delete Collection", systemImage: "trash", role: .destructive) {
                                deletionCandidate = collection
                            }
                            .disabled(browserStore.isManagingCollectionOrPlaylist(collection))
                        }
                    }
                    .task {
                        await browserStore.loadMoreCollectionsIfNeeded(
                            in: library,
                            currentItem: collection
                        )
                    }
                }

                if browserStore.isLoadingCollections(in: library) {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel("Loading more collections in \(library.title)")
                }
            }
        } header: {
            HStack {
                Text(library.title)
                Spacer()
                if browserStore.supportsCollectionManagement {
                    Button("New Collection", systemImage: "plus") {
                        presentedEditor = .create
                    }
                    .labelStyle(.iconOnly)
                    .disabled(browserStore.isCreatingCollection(in: library))
                    .accessibilityLabel("New collection in \(library.title)")
                }
            }
        }
        .task(id: library.id) {
            await browserStore.loadCollections(in: library)
        }
        .sheet(item: $presentedEditor) { request in
            PlexCollectionEditorSheet(
                request: request,
                library: library,
                browserStore: browserStore
            )
        }
        .confirmationDialog(
            "Delete Collection?",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { isPresented in
                    if !isPresented {
                        deletionCandidate = nil
                    }
                }
            ),
            presenting: deletionCandidate
        ) { collection in
            Button("Delete \(collection.title)", role: .destructive) {
                delete(collection)
            }
        } message: { collection in
            Text("This removes the collection from Plex. Its media files are not deleted.")
        }
        .alert(
            "Couldn’t Change Collection",
            isPresented: Binding(
                get: { mutationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        mutationErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(mutationErrorMessage ?? "Unknown Plex error.")
        }
    }

    private var collections: [PlexMediaItem] {
        browserStore.collections(in: library)
    }

    private func refresh() {
        Task {
            await browserStore.loadCollections(in: library, forceRefresh: true)
        }
    }

    private func delete(_ collection: PlexMediaItem) {
        deletionCandidate = nil
        Task {
            do {
                try await browserStore.deleteCollection(collection, in: library)
            } catch {
                mutationErrorMessage = error.localizedDescription
            }
        }
    }
}

struct PlexPlaylistsView: View {
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @State private var presentedEditor: PlexMediaItem?
    @State private var deletionCandidate: PlexMediaItem?
    @State private var mutationErrorMessage: String?

    var body: some View {
        Group {
            if browserStore.isLoadingPlaylists, browserStore.playlists.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading Playlists")
            } else if let errorMessage = browserStore.playlistsErrorMessage,
                      browserStore.playlists.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t Load Playlists", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: refresh)
                }
            } else if browserStore.playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list")
            } else {
                List(browserStore.playlists) { playlist in
                    NavigationLink(value: PlexNavigationRoute.media(PlexMediaRoute(item: playlist))) {
                        PlexMediaChildRow(
                            item: playlist,
                            settingsStore: settingsStore,
                            serverURL: connectionStore.resolvedServerURL
                        )
                    }
                    .contextMenu {
                        if browserStore.supportsPlaylistManagement(for: playlist) {
                            Button("Rename Playlist", systemImage: "pencil") {
                                presentedEditor = playlist
                            }
                            Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                                deletionCandidate = playlist
                            }
                            .disabled(browserStore.isManagingCollectionOrPlaylist(playlist))
                        }
                    }
                    .task {
                        await browserStore.loadMorePlaylistsIfNeeded(currentItem: playlist)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Playlists")
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Refresh Playlists",
                isEnabled: !browserStore.isLoadingPlaylists,
                perform: refresh
            )
        )
        .task {
            await browserStore.loadPlaylists()
        }
        .sheet(item: $presentedEditor) { playlist in
            PlexPlaylistEditorSheet(playlist: playlist, browserStore: browserStore)
        }
        .confirmationDialog(
            "Delete Playlist?",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { isPresented in
                    if !isPresented {
                        deletionCandidate = nil
                    }
                }
            ),
            presenting: deletionCandidate
        ) { playlist in
            Button("Delete \(playlist.title)", role: .destructive) {
                delete(playlist)
            }
        } message: { _ in
            Text("This permanently removes the playlist from Plex.")
        }
        .alert(
            "Couldn’t Change Playlist",
            isPresented: Binding(
                get: { mutationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        mutationErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(mutationErrorMessage ?? "Unknown Plex error.")
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh Playlists", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(browserStore.isLoadingPlaylists)
            }
        }
    }

    private func refresh() {
        Task {
            await browserStore.loadPlaylists(forceRefresh: true)
        }
    }

    private func delete(_ playlist: PlexMediaItem) {
        deletionCandidate = nil
        Task {
            do {
                try await browserStore.deletePlaylist(playlist)
            } catch {
                mutationErrorMessage = error.localizedDescription
            }
        }
    }
}

private enum CollectionEditorRequest: Identifiable {
    case create
    case rename(PlexMediaItem)

    var id: String {
        switch self {
        case .create:
            "create"
        case .rename(let collection):
            "rename:\(collection.ratingKey)"
        }
    }

    var title: String {
        switch self {
        case .create:
            "New Collection"
        case .rename:
            "Rename Collection"
        }
    }

    var initialName: String {
        switch self {
        case .create:
            ""
        case .rename(let collection):
            collection.title
        }
    }
}

private struct PlexCollectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: CollectionEditorRequest
    let library: PlexLibrary
    @Bindable var browserStore: PlexBrowserStore
    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    init(
        request: CollectionEditorRequest,
        library: PlexLibrary,
        browserStore: PlexBrowserStore
    ) {
        self.request = request
        self.library = library
        self.browserStore = browserStore
        _name = State(initialValue: request.initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($isNameFocused)
                    .onSubmit(save)
            }
            .formStyle(.grouped)
            .navigationTitle(request.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save", action: save)
                        .disabled(isSaving || name.nilIfBlank == nil)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 180)
        .onAppear { isNameFocused = true }
        .alert(
            "Couldn’t Save Collection",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown Plex error.")
        }
    }

    private func save() {
        guard !isSaving, name.nilIfBlank != nil else {
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                switch request {
                case .create:
                    _ = try await browserStore.createCollection(named: name, in: library)
                case .rename(let collection):
                    try await browserStore.renameCollection(collection, to: name, in: library)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PlexPlaylistEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    init(playlist: PlexMediaItem, browserStore: PlexBrowserStore) {
        self.playlist = playlist
        self.browserStore = browserStore
        _name = State(initialValue: playlist.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($isNameFocused)
                    .onSubmit(save)
            }
            .formStyle(.grouped)
            .navigationTitle("Rename Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save", action: save)
                        .disabled(isSaving || name.nilIfBlank == nil)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 180)
        .onAppear { isNameFocused = true }
        .alert(
            "Couldn’t Save Playlist",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown Plex error.")
        }
    }

    private func save() {
        guard !isSaving, name.nilIfBlank != nil else {
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await browserStore.renamePlaylist(playlist, to: name)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
