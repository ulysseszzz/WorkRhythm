# Changelog

All notable changes are documented here. The project follows Semantic Versioning from the first public release.

## [1.0.0] - 2026-10-15

First public GitHub release.

### Added

- Native macOS menu bar application for Work, Focus, Idle, Away, Moving and device-state timelines.
- Hot Corner correlation for lock-screen and display-sleep departures.
- Manual lock inference for keyboard shortcuts and menu commands using a five-second recent-input window.
- Hourly day overview with newest-first details and day/week/month statistics.
- Focus timer integrated with away, lock, lid and sleep states.
- Local hydration tracking with six drink types, a four-stop volume slider and twelve garden recipes.
- SQLite persistence, crash recovery, online backup, CSV export and diagnostic JSON export.
- Local-only privacy model with no analytics or network requests.

### Reliability

- Competing system sleep, lid-close and screen-saver events do not become manual Away sessions.
- Duplicate or reordered lock notifications can be upgraded when detailed manual-lock evidence arrives.
- Unknown process-offline gaps are explicit and are not counted as work.
- Cross-midnight and daylight-saving boundaries use calendar-aware duration slicing.

### Distribution

- Universal arm64/x86_64 application for macOS 14+.
- Published binary is ad-hoc signed and not notarized.
