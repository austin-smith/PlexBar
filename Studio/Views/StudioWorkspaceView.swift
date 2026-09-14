import SwiftUI

struct StudioWorkspaceView: View {
    @Bindable var store: StudioStore
    @Environment(\.openSettings) private var openSettings
    @State private var showNewTitle = false
    @State private var showReview = false
    @State private var showValidation = false
    @State private var showInspector = false

    var body: some View {
        VStack(spacing: 0) {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            collection.frame(minWidth: 430)
                .inspector(isPresented: $showInspector) {
                    StudioInspectorView(store: store)
                        .tint(.orange)
                        .inspectorColumnWidth(min: 300, ideal: 350, max: 460)
                }
        }
        .navigationTitle(store.windowTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Title", systemImage: "plus") { showNewTitle = true }.disabled(store.pack == nil || store.isBusy)
                    .help("New title")
                Button { showReview = true } label: {
                    HStack(spacing: 6) {
                        if store.hasActiveGenerations { ProgressView().controlSize(.small).accessibilityHidden(true) }
                        else { Image(systemName: "square.stack") }
                        if store.generationAttentionCount > 0 {
                            Text(store.generationAttentionCount, format: .number)
                                .monospacedDigit()
                        }
                    }
                }
                .accessibilityLabel(store.generationSummary == "Generations" ? "Generations" : "Generations, " + store.generationSummary)
                .help("Needs review")
                Button("Validate", systemImage: "checkmark.shield") {
                    Task { await store.validate(); showValidation = true }
                }.disabled(store.pack == nil || store.isBusy)
                    .help("Validate")
                Button("Reload Content", systemImage: "arrow.clockwise") { Task { await store.loadContent() } }
                    .disabled(store.isBusy || store.hasActiveGenerations)
                    .help("Reload")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Toggle Inspector", systemImage: "sidebar.trailing") {
                    showInspector.toggle()
                }
                .disabled(store.selectedItem == nil)
                .help(showInspector ? "Hide inspector" : "Show inspector")
            }
        }
        if store.isBusy || !store.statusMessage.isEmpty {
            statusBar
        }
        }
        .task { await store.loadContent() }
        .onChange(of: store.selection) {
            if store.selection == nil { showInspector = false }
        }
        .onChange(of: store.visibleItems.map(\.id)) {
            if let selection = store.selection, !store.visibleItems.contains(where: { $0.id == selection }) {
                store.selection = nil
            }
        }
        .sheet(isPresented: $showNewTitle) { StudioNewTitleSheet(store: store) }
        .sheet(isPresented: $showReview) { StudioReviewSheet(store: store) }
        .sheet(isPresented: $showValidation) { StudioValidationSheet(issues: store.validationIssues) }
        .alert("Studio couldn’t finish that action", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $store.category) {
                Section("Collection") {
                    ForEach(StudioCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.symbol)
                            .badge(category == .all ? store.items.count : store.items.filter { $0.category == category }.count)
                            .tag(category)
                    }
                }
                Section {
                    Button { showReview = true } label: { Label("Generations", systemImage: "clock.arrow.circlepath") }
                        .buttonStyle(.plain)
                        .badge(store.generationAttentionCount)
                }
            }.listStyle(.sidebar)
            Divider()
            Button { openSettings() } label: { Label("Settings…", systemImage: "gearshape") }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }

    private var collection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.category.rawValue)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(store.visibleItems.count) items").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a title or user", text: $store.search).textFieldStyle(.plain)
                if !store.search.isEmpty { Button("Clear", systemImage: "xmark.circle.fill") { store.search = "" }.labelStyle(.iconOnly).buttonStyle(.plain) }
            }.padding(10).background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 8)).padding(.horizontal, 24).padding(.bottom, 20)
            if store.visibleItems.isEmpty {
                ContentUnavailableView(store.pack == nil ? "Mock content unavailable" : "No matching content", systemImage: "square.grid.2x2", description: Text(store.pack == nil ? "Studio reads this checkout’s PlexBar/Resources/MockServer folder. Restore the files or rebuild Studio if you moved the checkout, then reload." : "Try another search or add a new title."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        if store.category == .all {
                            ForEach(collectionSections, id: \.category) { section in
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(section.category.rawValue)
                                            .font(.title3.weight(.semibold))
                                            .accessibilityAddTraits(.isHeader)
                                        Text("\(section.items.count)")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    gallery(items: section.items)
                                }
                            }
                        } else {
                            gallery(items: store.visibleItems)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 28)
                }
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var collectionSections: [(category: StudioCategory, items: [StudioGalleryItem])] {
        let items = store.visibleItems
        return StudioCategory.allCases.filter { $0 != .all }.compactMap { category in
            let matches = items.filter { $0.category == category }
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    private func gallery(items: [StudioGalleryItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 170), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
            ForEach(items) { item in
                StudioGalleryCard(item: item, selected: store.selection == item.id, revision: store.artworkRevision) {
                    store.selection = item.id
                    showInspector = true
                }
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
            if store.isBusy {
                ProgressView().controlSize(.small)
                Text(store.activity)
            } else {
                Image(systemName: store.didValidate && store.validationIssues.isEmpty ? "checkmark.circle.fill" : "circle.fill")
                    .foregroundStyle(store.didValidate && store.validationIssues.isEmpty ? Color.green : Color.secondary)
                    .font(.system(size: 9))
                Text(store.statusMessage)
            }
            Spacer()
        }.font(.caption).padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
        }
    }
}

private struct StudioGalleryCard: View {
    let item: StudioGalleryItem
    let selected: Bool
    let revision: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                StudioImageView(url: item.previewURL, contentMode: .fit, revision: revision)
                    .aspectRatio(item.ratio, contentMode: .fit)
                    .background(Color.primary.opacity(0.035))
                    // Reserve the ring and gap in both states; artwork keeps its full rectangular bounds.
                    .padding(6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.tint, lineWidth: 3)
                            .opacity(selected ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(item.subtitle.isEmpty ? item.category.rawValue : item.subtitle)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.padding(.horizontal, 6)
            }.contentShape(.rect)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(item.title), \(item.category.rawValue)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
