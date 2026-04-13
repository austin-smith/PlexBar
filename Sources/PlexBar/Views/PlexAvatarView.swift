import AppKit
import SwiftUI

struct PlexAvatarView: View {
    let thumb: String?
    let serverURL: URL?
    let serverToken: String
    let userToken: String
    let clientContext: PlexClientContext
    let size: CGFloat
    let imageClient: PlexImageClient

    @State private var image: Image?
    @State private var isLoading = false

    init(
        thumb: String?,
        serverURL: URL?,
        serverToken: String,
        userToken: String,
        clientContext: PlexClientContext,
        size: CGFloat = 30,
        imageClient: PlexImageClient = PlexImageClient()
    ) {
        self.thumb = thumb
        self.serverURL = serverURL
        self.serverToken = serverToken
        self.userToken = userToken
        self.clientContext = clientContext
        self.size = size
        self.imageClient = imageClient

        let resolvedRequest = Self.resolveRequest(
            thumb: thumb,
            serverURL: serverURL,
            serverToken: serverToken,
            userToken: userToken
        )
        let cachedImage = resolvedRequest.map { imageClient.cachedImage(from: [$0.url], token: $0.token) } ?? nil
        _image = State(initialValue: cachedImage.map(Image.init(nsImage:)))
    }

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: size * 0.42, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: requestKey) {
            await loadImage()
        }
    }

    private var resolvedRequest: AvatarRequest? {
        Self.resolveRequest(
            thumb: thumb,
            serverURL: serverURL,
            serverToken: serverToken,
            userToken: userToken
        )
    }

    private var requestKey: String {
        [
            resolvedRequest?.url.absoluteString,
            resolvedRequest?.token,
            clientContext.clientIdentifier,
            String(describing: size),
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    @MainActor
    private func loadImage() async {
        guard let resolvedRequest else {
            image = nil
            isLoading = false
            return
        }

        if let cachedImage = imageClient.cachedImage(from: [resolvedRequest.url], token: resolvedRequest.token) {
            image = Image(nsImage: cachedImage)
            isLoading = false
            return
        }

        isLoading = true
        image = nil

        if Task.isCancelled {
            isLoading = false
            return
        }

        if let loadedImage = await imageClient.fetchImage(
            from: [resolvedRequest.url],
            token: resolvedRequest.token,
            clientContext: clientContext
        ) {
            image = Image(nsImage: loadedImage)
        } else {
            image = nil
        }

        isLoading = false
    }

    private struct AvatarRequest {
        let url: URL
        let token: String
    }

    private static func resolveRequest(
        thumb: String?,
        serverURL: URL?,
        serverToken: String,
        userToken: String
    ) -> AvatarRequest? {
        guard let thumb = thumb?.nilIfBlank else {
            return nil
        }

        let imageURL: URL?
        if let absoluteURL = URL(string: thumb), absoluteURL.scheme != nil {
            imageURL = absoluteURL
        } else if let serverURL {
            imageURL = PlexURLBuilder.mediaURL(serverURL: serverURL, path: thumb)
        } else {
            imageURL = nil
        }

        guard let imageURL else {
            return nil
        }

        let host = imageURL.host?.lowercased() ?? ""
        let token = host.contains("plex.tv") ? userToken : serverToken
        return AvatarRequest(url: imageURL, token: token)
    }
}
