import Foundation

struct PlexDetailDiscoveryPresentation: Equatable {
    let hasContent: Bool
    let hasError: Bool
    let isLoading: Bool

    var isVisible: Bool {
        hasContent || hasError || isLoading
    }
}

extension PlexBrowserStore {
    func detailDiscoveryPresentation(for item: PlexMediaItem) -> PlexDetailDiscoveryPresentation {
        PlexDetailDiscoveryPresentation(
            hasContent: !mediaExtras(for: item).isEmpty || !relatedHubs(for: item).isEmpty,
            hasError: mediaExtrasErrorMessage(for: item) != nil
                || relatedContentErrorMessage(for: item) != nil,
            isLoading: isLoadingMediaExtras(for: item) || isLoadingRelatedContent(for: item)
        )
    }

    func resetDetailDiscoveryContent() {
        resetMediaExtras()
        resetRelatedContent()
        resetPeople()
    }

    func loadDetailDiscoveryContent(
        for item: PlexMediaItem,
        forceRefresh: Bool = false
    ) async {
        async let extrasLoad: Void = loadMediaExtras(
            for: item,
            forceRefresh: forceRefresh
        )
        async let relatedLoad: Void = loadRelatedContent(
            for: item,
            forceRefresh: forceRefresh
        )
        _ = await (extrasLoad, relatedLoad)
    }
}
