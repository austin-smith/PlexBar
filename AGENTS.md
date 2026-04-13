# PlexBar Agent Guide

This file defines project constraints for coding agents working in this repository.

## Reference Documentation

- Plex API documentation: `https://developer.plex.tv/pms/`

## Platform + App Contract

- PlexBar is a macOS-only app built with SwiftPM.
- Minimum supported platform is macOS 26+.
- The app is menu-bar-first and should remain an accessory app without a Dock icon unless otherwise explicitly requested.
- UI work should stay SwiftUI-first.
- Do not introduce AppKit UI implementations unless a maintainer explicitly asks.

## Project Boundaries

- App sources live in `Sources/PlexBar/`.
- Tests live in `Tests/PlexBarTests/`.
- Keep view code in `Views/`, stateful app logic in `Stores/`, API/auth code in `Services/`, and shared helpers in `Support/`.

## Code Expectations

- Prefer modern Swift 6 and SwiftUI APIs.
- Preserve the current Observation-based state flow.
- Keep behavior deterministic and easy to reason about.
- Avoid speculative abstractions.
- Do not add backward-compatibility code, compatibility shims, or legacy fallback paths unless explicitly requested.
- Do not add heuristic fallback logic, automatic failover paths, multi-strategy retries, or "best effort" guessing unless a maintainer explicitly asks for that behavior.
- When something fails, prefer surfacing the concrete failure and fixing the root cause over adding alternate code paths that mask the problem.

## Building

From repo root (`/Users/austinsmith/Developer/Repos/PlexBar`), build with:

```bash
swift build
```

To build and launch the app bundle:

```bash
script/build_and_run.sh
```

## Testing

From repo root (`/Users/austinsmith/Developer/Repos/PlexBar`), run:

```bash
swift test
```

Add tests when they protect meaningful behavior, parsing logic, or regressions. Avoid low-value tests for simple refactors or trivial helpers.
