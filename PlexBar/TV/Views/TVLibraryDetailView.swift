import PlexModels
import SwiftUI

struct TVLibraryDetailView: View {
    @Environment(TVAppStore.self) private var store
    let library: TVPlexLibrary
    @State private var options = PlexLibraryBrowseOptions.default
    @State private var definition: PlexLibraryBrowseDefinition?
    @State private var definitionError: String?
    @State private var definitionReloadID = UUID()
    @State private var presentedFilter: PlexLibraryFilterDefinition?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 20) {
                    Text(library.title).font(TVTypography.title)
                    Spacer()
                    sortMenu
                    filterMenu
                    Button {
                        Task { await store.loadLibrary(library, options: options, refresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                    .disabled(store.isLoading(library))
                }
                .font(TVTypography.action)
                .safeAreaPadding(.horizontal)
                .padding(.top, 32)
                .focusSection()
                if let definitionError {
                    errorRow("Couldn’t Load Browse Options", message: definitionError) { definitionReloadID = UUID() }
                }
                if let error = store.libraryErrors[library.id] {
                    errorRow("Couldn’t Load \(library.title)", message: error) {
                        Task {
                            await store.retryLibrary(library, options: options)
                        }
                    }
                }
                if store.isLoading(library), items.isEmpty {
                    TVLoadingView(title: "Loading \(library.title)…")
                } else if items.isEmpty, store.libraryErrors[library.id] == nil {
                    ContentUnavailableView {
                        Label(options.hasFilters ? "No Matching Items" : "Nothing Here", systemImage: "rectangle.stack.badge.minus")
                    } description: {
                        Text(options.hasFilters ? "No media matches the selected filters." : "This library does not contain any visible media.")
                    } actions: {
                        if options.hasFilters { Button("Clear Filters", action: clearFilters) }
                    }
                } else {
                    TVMediaGrid(items: items) { item in
                        guard store.libraryErrors[library.id] == nil else { return }
                        await store.loadMoreLibraryItems(library, currentItem: item)
                    }
                    .safeAreaPadding(.horizontal)
                    .safeAreaPadding(.vertical)
                    if store.isLoading(library) { ProgressView("Loading more…") }
                }
            }
        }
        .scrollClipDisabled()
        .background(TVCanvasBackground())
        .ignoresSafeArea(.container, edges: .top)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task(id: BrowseIdentity(connection: store.connection, options: options)) {
            await store.loadLibrary(library, options: options)
        }
        .task(id: DefinitionIdentity(connection: store.connection, reloadID: definitionReloadID)) {
            definition = nil
            definitionError = nil
            do {
                let result = try await store.libraryBrowseDefinition(library)
                try Task.checkCancellation()
                definition = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                definitionError = error.localizedDescription
            }
        }
        .sheet(item: $presentedFilter) { filter in
            TVLibraryFilterPicker(filter: filter, selectedValues: options.valueSelections(for: filter.id)) {
                options.setValueSelections($0, for: filter.id)
            }
        }
    }

    private var items: [PlexMediaItem] { store.libraryItems[library.id] ?? [] }

    private var sortMenu: some View {
        Menu {
            Button { options.sort = nil } label: { menuLabel("Default", selected: options.sort == nil) }
            ForEach(definition?.sorts ?? []) { sort in
                Button { options.sort = sort.selection() } label: {
                    menuLabel(sort.title, selected: options.sort?.sortID == sort.id)
                }
            }
            if let sort = definition?.sorts.first(where: { $0.id == options.sort?.sortID }) {
                Section("Direction") {
                    Button { options.sort = sort.selection(direction: .ascending) } label: {
                        menuLabel("Ascending", selected: options.sort?.direction == .ascending)
                    }
                    if sort.descendingKey != nil {
                        Button { options.sort = sort.selection(direction: .descending) } label: {
                            menuLabel("Descending", selected: options.sort?.direction == .descending)
                        }
                    }
                }
            }
        } label: { Image(systemName: "arrow.up.arrow.down") }
        .disabled(definition?.sorts.isEmpty != false)
        .accessibilityIdentifier("library-sort")
        .accessibilityLabel("Sort \(library.title)")
        .accessibilityValue(options.sort.flatMap { selection in definition?.sorts.first { $0.id == selection.sortID }?.title } ?? "Default")
    }

    private var filterMenu: some View {
        Menu {
            Section("Status") {
                ForEach(definition?.booleanFilters ?? []) { filter in
                    Toggle(filter.title, isOn: Binding(
                        get: { options.enabledBooleanFilterIDs.contains(filter.id) },
                        set: { enabled in
                            if enabled { options.enabledBooleanFilterIDs.insert(filter.id) }
                            else { options.enabledBooleanFilterIDs.remove(filter.id) }
                        }
                    ))
                }
            }
            Section("Details") {
                ForEach(definition?.valueFilters ?? []) { filter in
                    Button { presentedFilter = filter } label: {
                        let count = options.valueSelections(for: filter.id).count
                        menuLabel(count == 0 ? filter.title : "\(filter.title) (\(count))", selected: count > 0)
                    }
                }
            }
            Button("Clear Filters", action: clearFilters).disabled(!options.hasFilters)
        } label: {
            Image(systemName: options.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .disabled(definition?.filters.isEmpty != false)
        .accessibilityIdentifier("library-filter")
        .accessibilityLabel("Filter \(library.title)")
    }

    private func clearFilters() {
        options.enabledBooleanFilterIDs.removeAll()
        options.valueFilterSelections.removeAll()
    }

    @ViewBuilder private func menuLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") }
        else { Text(title) }
    }

    private func errorRow(_ title: String, message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(TVTypography.body)
                Text(message).font(TVTypography.caption).foregroundStyle(.secondary)
            }
            Button("Try Again", action: retry).font(TVTypography.action)
        }
        .safeAreaPadding(.horizontal)
    }

    private struct BrowseIdentity: Equatable {
        let connection: TVPlexConnection?
        let options: PlexLibraryBrowseOptions
    }
    private struct DefinitionIdentity: Equatable {
        let connection: TVPlexConnection?
        let reloadID: UUID
    }
}

private struct TVLibraryFilterPicker: View {
    @Environment(TVAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let filter: PlexLibraryFilterDefinition
    let apply: ([PlexLibraryFilterValue]) -> Void
    @State private var selectedIDs: Set<String>
    @State private var values: [PlexLibraryFilterValue] = []
    @State private var isLoaded = false
    @State private var error: String?
    @State private var searchText = ""
    @State private var reloadID = UUID()

    init(filter: PlexLibraryFilterDefinition, selectedValues: [PlexLibraryFilterValue], apply: @escaping ([PlexLibraryFilterValue]) -> Void) {
        self.filter = filter
        self.apply = apply
        _selectedIDs = State(initialValue: Set(selectedValues.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(filter.title).font(TVTypography.sectionTitle)
            TextField("Search \(filter.title)", text: $searchText)
                .font(TVTypography.body)
            Group {
                if let error {
                    ContentUnavailableView {
                        Label("Couldn’t Load \(filter.title)", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("Try Again") { reloadID = UUID() }
                    }
                } else if !isLoaded {
                    ProgressView("Loading \(filter.title)…")
                } else if values.isEmpty {
                    ContentUnavailableView("No \(filter.title) Values", systemImage: "line.3.horizontal.decrease")
                } else if filteredValues.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredValues) { value in
                        Button {
                            if !selectedIDs.insert(value.id).inserted {
                                selectedIDs.remove(value.id)
                            }
                        } label: {
                            HStack {
                                Text(value.title)
                                Spacer()
                                if selectedIDs.contains(value.id) { Image(systemName: "checkmark") }
                            }
                        }
                        .font(TVTypography.body)
                        .accessibilityIdentifier("filter-value.\(value.id)")
                        .accessibilityValue(selectedIDs.contains(value.id) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selectedIDs.contains(value.id) ? .isSelected : [])
                    }
                    .listStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            HStack(spacing: 24) {
                Button("Clear") { selectedIDs.removeAll() }.disabled(selectedIDs.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                Button(selectedIDs.isEmpty ? "Apply" : "Apply (\(selectedIDs.count))") {
                    apply(values.filter { selectedIDs.contains($0.id) })
                    dismiss()
                }.disabled(!isLoaded)
            }
            .font(TVTypography.action)
            .focusSection()
        }
        .padding(40)
        .frame(width: 800)
        .presentationSizing(.fitted)
        .task(id: reloadID) {
            error = nil
            do {
                let result = try await store.libraryFilterValues(filter)
                try Task.checkCancellation()
                values = result
                isLoaded = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private var filteredValues: [PlexLibraryFilterValue] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? values : values.filter { $0.title.localizedStandardContains(query) }
    }
}
