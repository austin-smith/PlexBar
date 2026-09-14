# PlexData

Local Swift package containing the data contracts shared by the apps in this repository. It uses Foundation and Swift 6, with no app, network, authentication, or resource-bundle dependencies.

- **PlexModels** owns decoded Plex media, account, library, session, and notification models, plus their decoding and text helpers. PlexBar and PlexBarTV import this module.
- **PlexMockData** depends on PlexModels and owns mock payload decoding and catalog validation. PlexBar's mock server and Studio use the same validation contract.

Both modules accept data supplied by their callers. They do not locate a checkout, load sample files, start a server, or modify resources. PlexBar owns its debug resource loader; Studio owns direct checkout access and local generation history. Playback orchestration, UI presentation, stores, and services stay in their app targets.

## Tests

From the repository root:

```sh
swift test --package-path Packages/PlexData
```

Tests import the public modules directly, without an app host. Session-model tests live in `Tests/PlexModelsTests`; catalog validation tests live in `Tests/PlexMockDataTests`. Integration tests using app stores, views, or sample resources remain with the corresponding app.
