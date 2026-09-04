import SwiftUI

enum PlexMediaOrganizationRequest: Identifiable {
    case collection
    case playlist

    var id: String {
        switch self {
        case .collection: "collection"
        case .playlist: "playlist"
        }
    }
}

struct PlexAddToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: PlexMediaItem
    let library: PlexLibrary
    @Bindable var browserStore: PlexBrowserStore
    @State private var newCollectionName = ""
    @State private var activeCollectionID: String?
    @State private var errorMessage: String?
    @FocusState private var isNewCollectionNameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("New Collection") {
                    HStack {
                        TextField("Name", text: $newCollectionName)
                            .focused($isNewCollectionNameFocused)
                            .onSubmit(createAndAdd)

                        Button("Create and Add", systemImage: "plus", action: createAndAdd)
                            .disabled(
                                newCollectionName.nilIfBlank == nil
                                    || activeCollectionID != nil
                                    || !browserStore.supportsCollectionManagement
                            )
                    }
                }

                Section("Collections") {
                    if browserStore.isLoadingCollections(in: library) && collections.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 70)
                            .accessibilityLabel("Loading Collections")
                    } else if let errorMessage = browserStore.collectionsErrorMessage(in: library),
                              collections.isEmpty {
                        ContentUnavailableView {
                            Label("Couldn’t Load Collections", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try Again", action: reload)
                        }
                    } else if collections.isEmpty {
                        ContentUnavailableView("No Editable Collections", systemImage: "rectangle.stack")
                    } else {
                        ForEach(collections) { collection in
                            Button {
                                add(to: collection)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(collection.title)
                                        if let itemCountLabel = collection.itemCountLabel {
                                            Text(itemCountLabel)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if activeCollectionID == collection.ratingKey {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .disabled(activeCollectionID != nil)
                        }
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 440)
        .onAppear { isNewCollectionNameFocused = true }
        .task {
            async let capabilities: Void = browserStore.loadLibraryProviderCapabilities()
            await browserStore.loadCollections(in: library)
            _ = await capabilities
        }
        .alert(
            "Couldn’t Add to Collection",
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

    private var collections: [PlexMediaItem] {
        browserStore.editableCollections(in: library)
    }

    private func reload() {
        Task {
            await browserStore.loadCollections(in: library, forceRefresh: true)
        }
    }

    private func add(to collection: PlexMediaItem) {
        guard activeCollectionID == nil else {
            return
        }
        activeCollectionID = collection.ratingKey
        Task {
            defer { activeCollectionID = nil }
            do {
                try await browserStore.add(item, to: collection, in: library)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createAndAdd() {
        guard activeCollectionID == nil, newCollectionName.nilIfBlank != nil else {
            return
        }
        activeCollectionID = "new"
        Task {
            defer { activeCollectionID = nil }
            do {
                try await browserStore.createCollection(
                    named: newCollectionName,
                    containing: item,
                    in: library
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PlexAddToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: PlexMediaItem
    @Bindable var browserStore: PlexBrowserStore
    @State private var newPlaylistName = ""
    @State private var activePlaylistID: String?
    @State private var errorMessage: String?
    @FocusState private var isNewPlaylistNameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("New Playlist") {
                    HStack {
                        TextField("Name", text: $newPlaylistName)
                            .focused($isNewPlaylistNameFocused)
                            .onSubmit(createPlaylist)

                        Button("Create", systemImage: "plus", action: createPlaylist)
                            .disabled(
                                newPlaylistName.nilIfBlank == nil
                                    || activePlaylistID != nil
                            )
                    }
                }

                Section("Playlists") {
                    if browserStore.isLoadingPlaylists && playlists.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 70)
                            .accessibilityLabel("Loading Playlists")
                    } else if let errorMessage = browserStore.playlistsErrorMessage,
                              playlists.isEmpty {
                        ContentUnavailableView {
                            Label("Couldn’t Load Playlists", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try Again", action: reload)
                        }
                    } else if playlists.isEmpty {
                        ContentUnavailableView("No Compatible Playlists", systemImage: "music.note.list")
                    } else {
                        ForEach(playlists) { playlist in
                            Button {
                                add(to: playlist)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.title)
                                        if let itemCountLabel = playlist.itemCountLabel {
                                            Text(itemCountLabel)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if activePlaylistID == playlist.ratingKey {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .disabled(activePlaylistID != nil)
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 440)
        .onAppear { isNewPlaylistNameFocused = true }
        .task {
            await browserStore.loadPlaylists()
        }
        .alert(
            "Couldn’t Add to Playlist",
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

    private var playlists: [PlexMediaItem] {
        browserStore.editablePlaylists(for: item)
    }

    private func reload() {
        Task {
            await browserStore.loadPlaylists(forceRefresh: true)
        }
    }

    private func add(to playlist: PlexMediaItem) {
        guard activePlaylistID == nil else {
            return
        }
        activePlaylistID = playlist.ratingKey
        Task {
            defer { activePlaylistID = nil }
            do {
                try await browserStore.add(item, to: playlist)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createPlaylist() {
        guard activePlaylistID == nil, newPlaylistName.nilIfBlank != nil else {
            return
        }
        activePlaylistID = "new"
        Task {
            defer { activePlaylistID = nil }
            do {
                try await browserStore.createPlaylist(
                    named: newPlaylistName,
                    containing: item
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
