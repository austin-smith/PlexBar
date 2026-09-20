import SwiftUI
import PlexMockData

struct StudioUserSheet: View {
    let store: StudioStore
    let original: PlexMockServerPayload.User
    let authenticatedUserID: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlexMockServerPayload.User?
    @State private var signedIn = false
    @State private var error: String?
    @State private var avatarChoices: [StudioAvatarArtwork.Choice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit User").font(.title2.bold())
            if let draftBinding = Binding($draft) {
                Form {
                    Section("Identity") {
                        TextField("Username", text: draftBinding.username)
                        StudioOptionalTextField(title: "Name", value: draftBinding.friendlyName)
                        StudioOptionalTextField(title: "Email", value: draftBinding.email)
                        Toggle("Use as signed-in user", isOn: $signedIn)
                            .disabled(original.id == authenticatedUserID)
                    }
                    Section("Avatar") {
                        Picker("Avatar", selection: draftBinding.avatar) {
                            Text("No avatar").tag(String?.none)
                            ForEach(avatarChoices) { choice in
                                Text(choice.title).tag(Optional(choice.path))
                            }
                        }
                        StudioImageView(url: store.artworkURL(for: draftBinding.wrappedValue.avatar), revision: store.artworkRevision)
                            .frame(width: 80, height: 80).clipShape(.circle)
                    }
                    ForEach(draftBinding.devices) { device in
                        StudioUserDeviceEditor(device: device, canRemove: !referencedDeviceIDs.contains(device.wrappedValue.id)) {
                            draft?.devices.removeAll { $0.id == device.wrappedValue.id }
                        }
                    }
                    Section {
                        Button("Add Device", systemImage: "plus", action: addDevice)
                        Text("Device and connection edits apply to all activity using that device. Devices referenced by activity or history cannot be removed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Changes", action: save).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(draft == nil || store.isBusy)
            }
        }
        .padding(24).frame(width: 660, height: 760)
        .onAppear {
            draft = original
            signedIn = original.id == authenticatedUserID
            do {
                guard let pack = store.pack else { throw StudioError.invalid("Mock content is not loaded.") }
                avatarChoices = try StudioAvatarArtwork.choices(in: pack)
            } catch { self.error = error.localizedDescription }
        }
    }

    private var referencedDeviceIDs: Set<Int> {
        Set(["activeSessions", "historyEvents"].flatMap { store.pack?.payload[$0]?.array ?? [] }
            .compactMap { $0["deviceID"]?.integer })
    }

    private func addDevice() {
        guard let devices = draft?.devices else { return }
        do {
            let id = try store.nextDeviceID(among: devices)
            draft?.devices.append(.init(id: id, title: "New device", machineIdentifier: "mock-device-\(id)"))
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard let draft else { return }
        do {
            try store.saveUser(draft, replacing: original, signedIn: signedIn, originalAuthenticatedUserID: authenticatedUserID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct StudioUserDeviceEditor: View {
    @Binding var device: PlexMockServerPayload.Device
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        Section("Device · \(device.id)") {
            TextField("Browser or device name", text: $device.title)
            TextField("Machine identifier", text: $device.machineIdentifier)
            StudioOptionalTextField(title: "Platform", value: $device.platform)
            StudioOptionalTextField(title: "Plex app / product", value: $device.product)
            StudioOptionalTextField(title: "IP address", value: $device.connection.address)
            StudioOptionalTextField(title: "Public IP address", value: $device.connection.remotePublicAddress)
            StudioOptionalTextField(title: "Location", value: $device.connection.resolvedLocation)
            Picker("Connection", selection: $device.connection.local) {
                Text("Unspecified").tag(Bool?.none)
                Text("Local").tag(Optional(true))
                Text("Remote").tag(Optional(false))
            }
            StudioOptionalFlagPicker(title: "Relayed", value: $device.connection.relayed)
            StudioOptionalFlagPicker(title: "Secure", value: $device.connection.secure)
            Button("Remove Device", role: .destructive, action: remove).disabled(!canRemove)
        }
    }
}

private struct StudioOptionalTextField: View {
    let title: String
    @Binding var value: String?

    var body: some View {
        TextField(title, text: Binding(get: { value ?? "" }, set: { value = $0.isEmpty ? nil : $0 }))
    }
}

private struct StudioOptionalFlagPicker: View {
    let title: String
    @Binding var value: Bool?

    var body: some View {
        Picker(title, selection: $value) {
            Text("Unspecified").tag(Bool?.none)
            Text("Yes").tag(Optional(true))
            Text("No").tag(Optional(false))
        }
    }
}
