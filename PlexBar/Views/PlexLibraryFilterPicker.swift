import SwiftUI

struct PlexLibraryFilterPicker: View {
    @Environment(\.dismiss) private var dismiss

    let filter: PlexLibraryFilterDefinition
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var searchStore: PlexLibrarySearchStore
    @State private var searchText = ""
    @State private var selectedValueIDs: Set<String>

    init(
        filter: PlexLibraryFilterDefinition,
        browserStore: PlexBrowserStore,
        searchStore: PlexLibrarySearchStore
    ) {
        self.filter = filter
        self.browserStore = browserStore
        self.searchStore = searchStore
        _selectedValueIDs = State(
            initialValue: Set(searchStore.selectedValues(for: filter).map(\.id))
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(filter.title)
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: "Search \(filter.title)"
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: dismiss.callAsFunction)
                            .keyboardShortcut(.cancelAction)
                    }

                    ToolbarItemGroup(placement: .confirmationAction) {
                        Button("Clear", action: clearSelection)
                            .disabled(selectedValueIDs.isEmpty)

                        Button(applyButtonTitle, action: applySelection)
                            .disabled(!browserStore.hasLoadedFilterValues(for: filter))
                            .keyboardShortcut(.defaultAction)
                    }
                }
        }
        .frame(minWidth: 520, minHeight: 520)
        .task(id: filter.id) {
            await browserStore.loadFilterValues(for: filter)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = browserStore.filterValuesErrorMessage(for: filter),
                  values.isEmpty {
            ContentUnavailableView {
                Label("Couldn’t Load \(filter.title)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again", action: retry)
            }
        } else if !browserStore.hasLoadedFilterValues(for: filter)
                    || (browserStore.isLoadingFilterValues(for: filter) && values.isEmpty) {
            ProgressView("Loading \(filter.title)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if values.isEmpty {
            ContentUnavailableView("No \(filter.title) Values", systemImage: "line.3.horizontal.decrease")
        } else if filteredValues.isEmpty {
            ContentUnavailableView.search(text: normalizedSearchText)
        } else {
            List(filteredValues) { value in
                Button {
                    toggle(value)
                } label: {
                    HStack {
                        Text(value.title)
                        Spacer()
                        if selectedValueIDs.contains(value.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    selectedValueIDs.contains(value.id) ? "Selected" : "Not selected"
                )
                .accessibilityAddTraits(
                    selectedValueIDs.contains(value.id) ? .isSelected : []
                )
            }
            .overlay(alignment: .top) {
                if browserStore.isLoadingFilterValues(for: filter) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Refreshing \(filter.title)")
                }
            }
        }
    }

    private var values: [PlexLibraryFilterValue] {
        browserStore.filterValues(for: filter)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredValues: [PlexLibraryFilterValue] {
        guard !normalizedSearchText.isEmpty else {
            return values
        }
        return values.filter {
            $0.title.localizedStandardContains(normalizedSearchText)
        }
    }

    private var applyButtonTitle: String {
        selectedValueIDs.isEmpty ? "Apply" : "Apply (\(selectedValueIDs.count))"
    }

    private func toggle(_ value: PlexLibraryFilterValue) {
        if !selectedValueIDs.insert(value.id).inserted {
            selectedValueIDs.remove(value.id)
        }
    }

    private func clearSelection() {
        selectedValueIDs.removeAll()
    }

    private func applySelection() {
        searchStore.setSelectedValues(
            values.filter { selectedValueIDs.contains($0.id) },
            for: filter
        )
        dismiss()
    }

    private func retry() {
        Task {
            await browserStore.loadFilterValues(for: filter, forceRefresh: true)
        }
    }
}
