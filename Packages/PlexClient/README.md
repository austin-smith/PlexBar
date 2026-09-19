# PlexClient

Shared implementations used by the native Mac and Apple TV clients. This package depends on `PlexModels` from `../PlexData`; it does not depend on either app target or on Studio.

- **PlexClientKit** owns shared authentication and request handling, playback contracts and native media helpers, and reusable presentation. The existing `Models`, `Services`, `Stores`, `Support`, `Playback`, and `Views` folders separate those responsibilities within the module.
- **PlexTopShelf** owns the TV app/extension snapshot, cache, links, and content builder. It has no client-runtime dependency, so the extension does not link authentication or playback code.

Each app supplies its identity and bundle version when constructing `PlexClientContext`, and its Keychain service when constructing device-identity storage. The Mac app supplies artwork fetching to the shared Now Playing loader. App scenes, browser stores, playback sessions, and resource loading remain app-owned.

`PlexData` continues to own decoded Plex models and mock-data contracts. Runtime and presentation code belongs here, not in the data package.

## Validation

```sh
swift build --package-path Packages/PlexClient
python3 script/check_source_boundaries.py
xcodebuild -project PlexBar.xcodeproj -scheme PlexBar -configuration Debug -destination 'platform=macOS' test
xcodebuild -project PlexBar.xcodeproj -scheme PlexBarTV -configuration Debug -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test
```

Run these from the repository root. App integration suites exercise the shared implementations; Top Shelf coverage runs in the TV suite. Live TV remote tests remain in the separate `PlexBarTVLiveUI` scheme.
