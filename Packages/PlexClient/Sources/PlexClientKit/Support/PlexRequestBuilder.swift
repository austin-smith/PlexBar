import PlexModels
import Foundation

public struct PlexRequestBuilder {
    public let clientContext: PlexClientContext

    public func request(
        url: URL,
        method: String = "GET",
        accept: String? = nil,
        token: String? = nil,
        timeout: TimeInterval = 15
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }

        clientContext.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        if !PlexRemoteService.isPlexHosted(url) {
            request.setValue(
                PlexClientContext.pmsAPIVersion,
                forHTTPHeaderField: "X-Plex-Pms-Api-Version"
            )
        }

        if let token = token?.nilIfBlank {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }

        return request
    }

    public init(clientContext: PlexClientContext) {
        self.clientContext = clientContext
    }
}
