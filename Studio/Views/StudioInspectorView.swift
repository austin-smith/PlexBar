import SwiftUI
import AppKit

struct StudioInspectorView: View {
    @Bindable var store: StudioStore
    @State private var showGenerate = false
    @State private var editingRecord: StudioCatalogRecord?
    @State private var editingUser: StudioUserEdit?

    var body: some View {
        Group {
            if let item = store.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Text("CONTENT DETAILS").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: item.category.symbol).foregroundStyle(.secondary)
                        }
                        if let record = store.selectedRecord, let pack = store.pack {
                            let assets = pack.artwork(for: record)
                            if assets.count > 1 {
                                artworkCarousel(assets)
                                    .id(record.id)
                            } else {
                                artworkPreview(url: item.previewURL, ratio: item.ratio)
                            }
                        } else {
                            artworkPreview(url: item.previewURL, ratio: item.ratio)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.system(size: 24, weight: .semibold, design: .rounded)).textSelection(.enabled)
                            Text(item.subtitle.isEmpty ? item.category.rawValue : item.subtitle).foregroundStyle(.secondary)
                        }
                        Button { showGenerate = true } label: { Label("Create Artwork", systemImage: "sparkles").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).controlSize(.large).disabled(store.isBusy)
                        if item.category == .users {
                            Divider()
                            Button("Edit Profile & Devices…", systemImage: "person.crop.circle") {
                                do {
                                    guard let id = Int(item.id.dropFirst("user:".count)) else {
                                        throw StudioError.invalid("The selected user ID is invalid.")
                                    }
                                    guard let authenticatedID = store.pack?.payload["authenticatedUserID"]?.integer else {
                                        throw StudioError.invalid("The mock signed-in user ID is missing.")
                                    }
                                    editingUser = try StudioUserEdit(user: store.userProfile(id: id), authenticatedUserID: authenticatedID)
                                } catch { store.errorMessage = error.localizedDescription }
                            }.disabled(store.isBusy)
                            Text("Manage identity, avatar, devices, and connection details shared by activity and history.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if let record = store.selectedRecord {
                            Divider()
                            HStack {
                                Text("Metadata").font(.headline)
                                Spacer()
                                Button("Edit") { editingRecord = record }.disabled(store.isBusy)
                            }
                            if let summary = record.metadata["summary"]?.string, !summary.isEmpty {
                                Text(summary).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            LabeledContent("Catalog ID", value: record.id).font(.caption)
                            LabeledContent("Media type", value: record.type.capitalized).font(.caption)
                            if let pack = store.pack {
                                let children = pack.records.filter { $0.parentID == record.id }
                                if !children.isEmpty {
                                    Divider()
                                    Text(record.type == "album" ? "Chapters" : "Seasons").font(.headline)
                                    ForEach(children) { child in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Button { editingRecord = child } label: {
                                                HStack { Text(child.title); Spacer(); Image(systemName: "pencil").foregroundStyle(.secondary) }
                                            }.buttonStyle(.plain)
                                            ForEach(pack.records.filter { $0.parentID == child.id }) { leaf in
                                                Button(leaf.title) { editingRecord = leaf }.buttonStyle(.link).font(.caption)
                                            }
                                        }.padding(.vertical, 4)
                                    }
                                }
                            }
                            Divider()
                            Text("Sources").font(.headline)
                            ForEach(record.sources, id: \.self) { source in
                                if let url = URL(string: source) {
                                    Link(destination: url) {
                                        HStack(alignment: .top) {
                                            Image(systemName: "arrow.up.right.square")
                                            Text(url.host ?? source).lineLimit(2)
                                        }.font(.caption)
                                    }.help(source)
                                }
                            }
                        }
                        Spacer(minLength: 10)
                    }.padding(24)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text("Artwork and catalog").font(.system(size: 23, weight: .medium, design: .rounded)).multilineTextAlignment(.center)
                    Text("Select a title to explore its artwork,\nmetadata, and sources.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showGenerate) {
            if let item = store.selectedItem { StudioGenerateSheet(store: store, item: item) }
        }
        .sheet(item: $editingUser) { edit in
            StudioUserSheet(store: store, original: edit.user, authenticatedUserID: edit.authenticatedUserID)
        }
        .sheet(item: $editingRecord) { record in StudioRecordSheet(store: store, record: record) }
    }

    private func artworkPreview(url: URL?, ratio: Double) -> some View {
        StudioImagePreview(url: url, revision: store.artworkRevision)
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: 275 * ratio)
            .clipShape(.rect(cornerRadius: 8))
            .frame(maxWidth: .infinity)
    }

    private func artworkCarousel(_ assets: [StudioAsset]) -> some View {
        let widestRatio = assets.map(\.role.ratio).max() ?? 1
        let previewItems = assets.compactMap { store.artworkURL(for: $0.path) }

        return ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(assets) { asset in
                    StudioImagePreview(
                        url: store.artworkURL(for: asset.path),
                        revision: store.artworkRevision,
                        previewItems: previewItems
                    )
                        .aspectRatio(asset.role.ratio, contentMode: .fit)
                        .containerRelativeFrame(.horizontal) { width, _ in
                            // Fit the widest artwork while leaving a glimpse of its neighbor.
                            min(275, (width - 24) / widestRatio) * asset.role.ratio
                        }
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityLabel("View larger \(asset.role.title.lowercased())")
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .accessibilityLabel("Artwork")
    }
}
