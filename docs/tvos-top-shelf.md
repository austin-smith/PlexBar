# Apple TV Top Shelf

Place PlexBar in the first row of the Apple TV Home Screen and focus its icon. Top Shelf shows Continue Watching followed by the server's promoted Recently Added movie, TV, and music shelves. Move up to browse the cards. Select opens details; Play/Pause resumes using PlexBar's normal playback preparation, quality settings, and queue handling.

When no content is available, the static image is a centered PlexBar logo on a plain dark background. The asset catalog contains standard (1920 × 720) and wide (2320 × 720) variants, each with 1× and 2× exports.

## Implementation

`PlexBarTV` embeds the `PlexBarTopShelf` app extension. Its principal class subclasses `TVTopShelfContentProvider`, and its extension point is `com.apple.tv-top-shelf`, matching the current Xcode TV Top Shelf template.

The app publishes a snapshot after a successful Home refresh, including on connection, return to the foreground, and completion of the final playback timeline report. Marking a title watched also refreshes the feed. Selection uses Plex hub identifiers rather than localized titles, preserves the server's Recently Added order, and limits publication to 10 items per shelf and 40 overall. Duplicate titles are identified by their server rating key. Episodes use series posters to avoid exposing episode stills.

`TVTopShelfPublisher` downloads artwork through the existing authenticated Plex client, with four concurrent image requests and a ten-second timeout per request. It writes immutable images before atomically replacing the snapshot, then calls `topShelfContentDidChange()`. Cancelling publication prevents an older request from restoring content after a session change. Old images are retained for a day to allow the Home Screen to finish displaying earlier snapshots; unreferenced older images are pruned on publication.

The app and extension share `group.com.crapshack.PlexBar.tv`. The cache lives in `Library/Caches/TopShelf` inside that group. It contains presentation metadata and local artwork only: no Plex tokens, server URLs, or authenticated image URLs. The extension reads this snapshot without network requests, so it can respond promptly while the app is suspended. It reflects the last successful app refresh; it does not independently poll Plex while the app is closed.

Sign-out and changes of the connected server clear the snapshot and notify tvOS. Missing content, unavailable artwork, and purged caches yield no dynamic content, allowing tvOS to display the bundled static image. Publication and extension failures are recorded under the `TopShelf` log category.

Links use `plexbar-tv://topshelf/display?server=SERVER_ID&item=RATING_KEY` and the corresponding `/play` action. The app validates the link, waits for saved-session restoration, checks the connected server, and fetches current metadata. A title from another server produces an error instead of opening an unrelated title with the same rating key.

## Signing

Both targets must be signed by the same development team, with App Groups enabled and the shared group registered for both App IDs:

- App: `com.crapshack.PlexBar.tv`
- Extension: `com.crapshack.PlexBar.tv.topshelf`
- App Group: `group.com.crapshack.PlexBar.tv`

Use provisioning profiles that include the group when installing on an Apple TV or distributing the app. Keep the extension's marketing version and build number equal to the containing app. Simulator signing does not prove device provisioning is configured.

## Verification

```sh
xcodebuild -project PlexBar.xcodeproj -scheme PlexBarTV -configuration Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' test
```

`TVTopShelfTests` covers hub selection, deduplication, limits, artwork availability and scale variants, progress, action URLs, invalid links, cache clearing, cancellation during publication, and routing across session restoration.

For the system integration check:

1. Build and launch the app, connect to Plex, and let Home load.
2. Return to the tvOS Home Screen and focus PlexBar in the first row. Verify posters, progress, and Recently Added content.
3. Move up and select a card. Verify that the app opens the matching detail page.
4. Terminate the app and open a Top Shelf card again to verify cold-launch routing.
5. Use Play/Pause on a partially watched title and verify playback resumes.
6. Sign out or switch servers and verify that the previous session's content disappears.

Apple references: [TV Services](https://developer.apple.com/documentation/tvservices), [Top Shelf design](https://developer.apple.com/design/human-interface-guidelines/top-shelf), and [TVTopShelfContentProvider](https://developer.apple.com/documentation/tvservices/tvtopshelfcontentprovider).
