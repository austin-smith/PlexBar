import Foundation

struct PlexRequestBuilder {
    let clientContext: PlexClientContext

    func request(
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

        if let token = token?.nilIfBlank {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }

        return request
    }
}
