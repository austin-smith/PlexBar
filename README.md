<h1 align="center">
  <img src="docs/images/plexbar-app-icon-balloon.png" width="128" alt="PlexBar Icon">
  <br><span style="font-family: monospace;">PlexBar</span>
</h1>

PlexBar is a lightweight macOS menu bar app for Plex server telemetry.

<p align="center">
  <img src="./docs/screenshots/screen-grab-streams.png" alt="Active streams" height="420" />
  <img src="./docs/screenshots/screen-grab-history.png" alt="Playback history" height="420" />
</p>

## Features

- Native macOS menu bar app
- Plex sign-in and server discovery
- Live view of active sessions with playback details

## Requirements

- macOS 26+

## Build, Run, and Package

Copy `.env.example` to `.env.local` and update values as necessary.

To build and run the app:

```bash
script/build_and_run.sh
```

To run with mock data:

```bash
script/build_and_run.sh --mock
```

To package the app as a `dmg`:

```bash
script/build_dmg.sh
```
