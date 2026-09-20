import PlexClientKit
import Foundation

struct PlexArtworkPrefetchRequest: Hashable, Sendable {
    let candidateURLs: [URL]
    let token: String
    let clientContext: PlexClientContext
    let maximumPixelSize: Int
}

actor PlexArtworkPrefetcher {
    static let shared = PlexArtworkPrefetcher()

    private let imageClient: PlexImageClient
    private let maximumConcurrentRequests: Int
    private let maximumQueuedRequests: Int
    private var activeRequests: Set<PlexArtworkPrefetchRequest> = []
    private var queue: [PlexArtworkPrefetchRequest] = []

    init(
        imageClient: PlexImageClient = PlexImageClient(),
        maximumConcurrentRequests: Int = 4,
        maximumQueuedRequests: Int = 24
    ) {
        self.imageClient = imageClient
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.maximumQueuedRequests = max(0, maximumQueuedRequests)
    }

    func prefetch(_ requests: [PlexArtworkPrefetchRequest]) {
        var prioritizedRequests: [PlexArtworkPrefetchRequest] = []
        for request in requests where !prioritizedRequests.contains(request) {
            guard !activeRequests.contains(request),
                  imageClient.cachedCGImageResult(
                    from: request.candidateURLs,
                    token: request.token,
                    maximumPixelSize: request.maximumPixelSize
                  ) == nil else {
                continue
            }

            prioritizedRequests.append(request)
        }

        let prioritizedSet = Set(prioritizedRequests)
        queue.removeAll { prioritizedSet.contains($0) }
        queue.insert(contentsOf: prioritizedRequests, at: 0)
        if queue.count > maximumQueuedRequests {
            queue.removeLast(queue.count - maximumQueuedRequests)
        }
        startQueuedRequests()
    }

    private func startQueuedRequests() {
        while activeRequests.count < maximumConcurrentRequests,
              let request = queue.first {
            queue.removeFirst()
            activeRequests.insert(request)

            Task(priority: .utility) { [imageClient] in
                _ = await imageClient.fetchCGImageResult(
                    from: request.candidateURLs,
                    token: request.token,
                    clientContext: request.clientContext,
                    maximumPixelSize: request.maximumPixelSize
                )
                requestDidFinish(request)
            }
        }
    }

    private func requestDidFinish(_ request: PlexArtworkPrefetchRequest) {
        activeRequests.remove(request)
        startQueuedRequests()
    }
}
