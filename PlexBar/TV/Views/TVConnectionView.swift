import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct TVConnectionView: View {
    @Environment(TVAppStore.self) private var store

    var body: some View {
        Group {
            if !store.availableServers.isEmpty {
                TVServerSelectionView(servers: store.availableServers)
            } else if store.connectionState == .connecting {
                TVConnectingView()
            } else if store.hasAuthorizedAccount, !store.isPairing {
                TVReconnectView()
            } else {
                TVDeviceAuthorizationView(code: store.signInCode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TVCanvasBackground())
    }
}

private struct TVDeviceAuthorizationView: View {
    @Environment(TVAppStore.self) private var store
    let code: String?

    var body: some View {
        VStack(spacing: 28) {
            TVBrandMark(size: 64)

            Text("Sign In to Plex")
                .font(.title)

            if let code, let linkURL = PlexRemoteService.linkURL(pinCode: code) {
                TVDeviceAuthorizationQRCode(url: linkURL)

                Text("Scan the code, or visit plex.tv/link and enter")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text(code)
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .tracking(12)
                    .accessibilityLabel("Plex link code \(code)")
            } else if store.isPairing {
                ProgressView("Requesting a secure code…")
                    .controlSize(.large)
            } else {
                Button("Get a New Code", systemImage: "arrow.clockwise") {
                    store.startPlexDeviceAuthorization()
                }
            }

            Text("After you approve this Apple TV, PlexBar discovers your servers automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .safeAreaPadding()
    }
}

private struct TVDeviceAuthorizationQRCode: View {
    private let image: CGImage?

    init(url: URL) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            image = nil
            return
        }
        image = CIContext().createCGImage(outputImage, from: outputImage.extent)
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.black)
            }
        }
        .padding(16)
        .frame(width: 220, height: 220)
        .background(.white, in: .rect(cornerRadius: 12))
        .accessibilityElement()
        .accessibilityLabel("QR code to sign in to Plex")
        .accessibilityHint("Scan this code with a phone camera")
    }
}

private struct TVConnectingView: View {
    var body: some View {
        TVLoadingView(title: "Connecting to Plex…")
    }
}

private struct TVReconnectView: View {
    @Environment(TVAppStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("Can’t Reach Your Plex Server", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Your account is still linked. PlexBar can discover the server again.")
        } actions: {
            Button("Try Again", systemImage: "arrow.clockwise") {
                Task { await store.reconnectAuthorizedAccount() }
            }
        }
    }
}

private struct TVServerSelectionView: View {
    @Environment(TVAppStore.self) private var store
    let servers: [PlexServerResource]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(servers) { server in
                        Button {
                            select(server)
                        } label: {
                            Label {
                                Text(server.name)
                            } icon: {
                                Image(systemName: server.preferredConnection?.local == true
                                    ? "house.fill"
                                    : "network")
                            }
                        }
                    }
                } header: {
                    Text("Available Servers")
                } footer: {
                    Text("PlexBar remembers your selection on this Apple TV.")
                }
            }
            .navigationTitle("Choose a Plex Server")
        }
    }

    private func select(_ server: PlexServerResource) {
        Task { await store.selectServer(server) }
    }
}
