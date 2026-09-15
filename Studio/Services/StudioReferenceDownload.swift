import Foundation

enum StudioReferenceDownload {
    /// Returns a temporary PNG owned by the caller. Generation copies it into the job's references.
    static func load(_ address: String, session: URLSession = .shared) async throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            throw StudioError.invalid("Enter an HTTP or HTTPS image URL.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw StudioError.invalid("The image URL did not return an HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw StudioError.invalid("The image could not be downloaded (HTTP \(response.statusCode)).")
        }
        let file = FileManager.default.temporaryDirectory.appending(path: "studio-reference-\(UUID().uuidString).png")
        do {
            try data.write(to: file, options: .atomic)
            let normalized: Data
            do { normalized = try StudioFiles.normalizedReference(at: file) }
            catch { throw StudioError.invalid("The URL did not return a readable image. Use a direct image URL.") }
            try Task.checkCancellation()
            try normalized.write(to: file, options: .atomic)
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}
