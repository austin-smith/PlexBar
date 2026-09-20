# PlexBar Studio

PlexBar Studio is a standalone macOS app for editing PlexBar’s mock catalog and generating artwork. It opens the existing content in this checkout and saves approved changes directly to it. Catalog research and artwork generation use the installed Codex App Server and its signed-in account.

## Run Studio

Studio requires macOS 26 or later. The **PlexBarStudio** scheme in `PlexBar.xcodeproj` builds and runs the app.

To build and launch from the repository root:

```bash
xcodebuild -project PlexBar.xcodeproj -scheme PlexBarStudio -configuration Debug -destination 'platform=macOS' -derivedDataPath build/studio build
open 'build/studio/Build/Products/Debug/PlexBar Studio.app'
```

Studio uses the checkout it was built from. Moving the checkout requires rebuilding Studio.

## Edit and generate content

- **Save Changes** writes metadata edits directly to the catalog.
- **Users → Edit Profile & Devices…** edits names, account details, avatars, and reusable devices with their connection details. Choose a profile as the signed-in user. Active sessions and history reference these devices; referenced devices cannot be removed. Saving a profile updates all activity that uses it.
- **New Title** researches a catalog draft with sources.
- **Create Artwork** accepts a local reference image or a direct image URL, plus optional additional instructions. Progress and review remain available after returning to the collection. Up to six generations run simultaneously; further requests wait in the queue. Completed artwork can be accepted, revised, or discarded.
- **Generations** contains results for review, revision, rejection, or acceptance. **Accept & Save** writes approved content to PlexBar’s mock resources.

Quitting stops active generations. Interrupted requests remain available for an explicit retry.

Pending and rejected generations leave the current catalog and artwork untouched.

Changes made outside Studio block conflicting saves. **Reload Content** loads the current files and preserves generation history.

**Validate** checks metadata, relationships, and artwork.

## Settings

Settings are available through **PlexBar Studio → Settings…** and **Settings…** in the sidebar:

- **Artwork** edits the Avatar and Reference Artwork prompts in [`artwork-instructions.json`](artwork-instructions.json). Dimensions follow the selected artwork type. **View Prompt…** in Create Artwork shows the assembled prompt before generation; it is recorded in generation history.
- **Codex** shows status, account, and installation details. Checks run when the tab opens and after changing the executable; **Refresh** checks again.

Studio keeps pending generations, references, and conversation history locally in the ignored `.studio` directory within the mock resources.

## Test

The automated suite runs from the repository root. Codex protocol tests use a simulated App Server.

```bash
xcodebuild -project PlexBar.xcodeproj -scheme PlexBarStudio -configuration Debug -destination 'platform=macOS' test
```

The live integration test is opt-in and consumes Codex usage:

```bash
TEST_RUNNER_PLEXBAR_STUDIO_LIVE_TEST=1 xcodebuild -project PlexBar.xcodeproj -scheme PlexBarStudio -configuration Debug -destination 'platform=macOS' -only-testing:PlexBarStudioTests/StudioLiveTests test
```
