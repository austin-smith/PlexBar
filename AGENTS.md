# PlexBar Agent Guide

This file defines project constraints for coding agents working in this repository.

## Reference Documentation

- [Plex API OpenAPI spec](docs/plex/openapi.json)
- [Plex API documentation](https://developer.plex.tv/pms/)

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

## Branches, Commits, and Pull Requests

- Use plain lowercase kebab-case for branch names. Keep names descriptive and do not include issue numbers, prefixes, or namespaces such as `feature/`, `fix/`, usernames, or agent names.
- Before every commit or amend, show the exact current diff and validation, then get explicit approval. Branch or pull-request requests are not commit approval; later changes require fresh approval.
- Never amend, rebase, squash, reset, rewrite history, or force-push without explicit approval for that exact operation.
- Write commit messages entirely lowercase. Use the imperative mood for the subject, keep each commit focused on one logical change, do not use type or scope prefixes, and do not end the subject with a period. Add a body when the reason or important tradeoffs are not clear from the subject.
- Keep each pull request focused on one coherent change.
- Write concise, specific, imperative pull request titles in sentence case. Do not use prefixes or trailing periods, and make the title understandable without the branch name.
- Pull request descriptions must include `What Changed`, `Why`, and `Validation`. Include `UI Changes` only when the pull request changes the UI. Keep descriptions concise, self-contained, complete, and accurate to the final diff.
- Link any related issues in the pull request description; do not include issue numbers in branch names.
- Review the complete diff before opening a pull request. Update the title and description whenever the scope changes, and remove unrelated changes.

## Issues

- Search open and closed issues before creating a new issue.
- Keep each issue focused on one problem or change.
- Use a concise, specific, sentence-case title without type prefixes.
- Give enough context to understand the issue without first inspecting the code.
- For bugs, describe the current and expected behavior. Include reproduction steps, environment details, and supporting evidence when available.
- For enhancements, explain the problem or goal, the desired outcome, and clear acceptance criteria.
- For UI issues, include screenshots. Include a short video when motion or interaction is relevant.
- Link any related issues and pull requests.
- Apply the appropriate existing label when creating an issue: `bug` for bugs and `enhancement` for feature requests.

## Building

From repo root (`/Users/austinsmith/Developer/Repos/PlexBar`), build with:

```bash
swift build
```

To build and launch the app bundle:

```bash
script/build_and_run.sh
```

## Sparkle Updates

- PlexBar uses Sparkle for auto-updates of Developer ID releases.
- Sparkle appcast/release workflow is documented in `docs/sparkle-updates.md`.
- Sparkle update metadata is injected by `script/build_and_run.sh` at bundle generation time; keep it out of checked-in source plist files.
- `script/build_and_run.sh` loads `.env.local` when present for local Sparkle build metadata.

## Testing

From repo root (`/Users/austinsmith/Developer/Repos/PlexBar`), run:

```bash
swift test
```

Add tests when they protect meaningful behavior, parsing logic, or regressions. Avoid low-value tests for simple refactors or trivial helpers.
