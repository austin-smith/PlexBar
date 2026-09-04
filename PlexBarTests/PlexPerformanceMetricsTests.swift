import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexPerformanceMetricsTests {
    @MainActor
    @Test func libraryQueryCacheRemainsBoundedAcrossThousandsOfReturnedItems() async throws {
        let store = try makeBrowserStore(transientRequestLimit: 8)
        let library = makeLibrary()

        await store.load(library)
        for queryIndex in 0..<64 {
            await store.load(library, searchQuery: "query-\(queryIndex)")
        }

        let metrics = store.cacheMetrics
        #expect(metrics.libraryRequestCount == 9)
        #expect(metrics.transientLibraryRequestCount == 8)
        #expect(metrics.libraryItemOccurrenceCount == 900)
        #expect(metrics.uniqueLibraryItemCount == 900)
        #expect(metrics.transientRequestCountsByLibraryID == [library.id: 8])
        #expect(metrics.transientRequestLimitPerLibrary == 8)
        #expect(store.items(in: library).count == 100)
        #expect(store.items(in: library, searchQuery: "query-0").isEmpty)
        #expect(store.items(in: library, searchQuery: "query-63").count == 100)
    }

    @Test func timelineCadenceRetainsConstantStateAcrossTwentyFourHoursOfTicks() {
        var cadence = PlexTimelineReportCadence()
        let start = ContinuousClock.now
        var reportCount = 0

        for second in 0...86_400 {
            let instant = start.advanced(by: .seconds(second))
            guard cadence.shouldReport(state: .playing, at: instant) else {
                continue
            }
            cadence.record(state: .playing, at: instant)
            reportCount += 1
        }

        #expect(reportCount == 8_641)
        #expect(cadence.lastReportedState == .playing)
        #expect(cadence.lastReportInstant == start.advanced(by: .seconds(86_400)))
    }

    @Test func timelineCadenceReportsStateChangesImmediatelyAndResetsPerMediaItem() {
        var cadence = PlexTimelineReportCadence()
        let start = ContinuousClock.now
        cadence.record(state: .playing, at: start)

        let stateChange = start.advanced(by: .seconds(1))
        #expect(cadence.shouldReport(state: .paused, at: stateChange))
        cadence.record(state: .paused, at: stateChange)
        #expect(!cadence.shouldReport(state: .paused, at: start.advanced(by: .seconds(10))))
        #expect(cadence.shouldReport(state: .paused, at: start.advanced(by: .seconds(11))))

        cadence.reset()
        #expect(cadence.shouldReport(state: .playing, at: stateChange))
        #expect(cadence.lastReportedState == nil)
        #expect(cadence.lastReportInstant == nil)
    }

    @MainActor
    private func makeBrowserStore(transientRequestLimit: Int) throws -> PlexBrowserStore {
        PerformanceMockURLProtocol.requestHandler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Plex-Container-Total-Size": "100"]
            ))
            switch request.url?.path {
            case "/media/providers":
                return (response, Self.mediaProvidersData)
            case "/library/sections/26/filters":
                return (response, Self.libraryFiltersData)
            case "/library/sections/26/sorts":
                return (response, Self.librarySortsData)
            default:
                return (response, Self.libraryPageData(for: request))
            }
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PerformanceMockURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        let suiteName = "PlexBarTests.performanceMetrics.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let credentials = PlexStoredCredentials(
            userToken: "user-token",
            serverToken: "server-token"
        )
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        settings.selectedServerIdentifier = "server-id"
        settings.selectedServerName = "Server"
        let connectionStore = PlexConnectionStore(settings: settings)
        connectionStore.activeConnection = PlexResolvedConnection(
            serverID: "server-id",
            url: try #require(URL(string: "https://plex.local:32400")),
            kind: .local,
            validatedAt: Date()
        )
        return PlexBrowserStore(
            connectionStore: connectionStore,
            client: PlexAPIClient(session: session),
            pageSize: 100,
            transientLibraryRequestLimit: transientRequestLimit
        )
    }

    private func makeLibrary() -> PlexLibrary {
        PlexLibrary(
            id: "26",
            title: "Movies",
            type: .movie,
            compositePath: nil,
            artPath: nil,
            thumbPath: nil,
            itemCount: 100,
            secondaryCount: nil,
            secondaryCountLabel: nil,
            updatedAt: nil,
            scannedAt: nil,
            contentChangedAt: nil,
            latestAddedAt: nil,
            latestItemTitle: nil
        )
    }

    private static let mediaProvidersData = Data(#"""
    {
      "MediaContainer": {
        "MediaProvider": [{
          "identifier": "com.plexapp.plugins.library",
          "Feature": [{
            "type": "content",
            "Directory": [{
              "id": "26",
              "key": "/library/sections/26",
              "Pivot": [{
                "id": "Library",
                "key": "/library/sections/26/all?type=1",
                "type": "list"
              }]
            }]
          }]
        }]
      }
    }
    """#.utf8)

    private static let libraryFiltersData = Data(#"{"MediaContainer":{"Directory":[]}}"#.utf8)
    private static let librarySortsData = Data(#"{"MediaContainer":{"Directory":[]}}"#.utf8)

    private static func libraryPageData(for request: URLRequest) -> Data {
        let query = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "title" })?.value
        } ?? "default"
        let metadata = (0..<100).map { itemIndex in
            let identifier = "\(query)-\(itemIndex)"
            return #"{"ratingKey":"\#(identifier)","type":"movie","title":"Item \#(identifier)"}"#
        }.joined(separator: ",")
        return Data(#"{"MediaContainer":{"Metadata":[\#(metadata)]}}"#.utf8)
    }
}

private final class PerformanceMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
