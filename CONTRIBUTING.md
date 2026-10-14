# Contributing

Contributions are welcome. Keep changes focused and preserve WorkRhythm's local-first privacy model.

## Development setup

Requirements:

- macOS 14 or later
- Xcode 15 or later
- Python 3 for project generation and UI tooling

Run:

```bash
swift test --scratch-path /tmp/WorkRhythm-tests
python3 Tools/generate_project.py
git diff --exit-code -- WorkRhythm.xcodeproj
xcodebuild -project WorkRhythm.xcodeproj -scheme WorkRhythm \
  -configuration Debug -derivedDataPath /tmp/WorkRhythm-DerivedData build
```

## Pull requests

- Describe the user-visible behavior and tradeoffs.
- Add focused tests for state-machine, persistence or statistics changes.
- Do not add telemetry, remote storage or new permissions without an explicit design discussion.
- Do not commit local databases, logs, exported diagnostics, build products or signing material.
- Keep UI changes usable at 300 points wide and verify light/dark appearances.
- Document heuristic limitations; do not present inferred Away states as physical-location facts.

## Lock detection changes

Include tests for event ordering and competing events. At minimum cover:

- Hot Corner lock/display sleep
- Recent-input keyboard/menu lock
- Automatic idle lock
- Screen saver
- System sleep and lid close
- Duplicate and out-of-order notifications

Real hardware checks are encouraged but must use isolated test data. Do not fabricate production history.

## Commit style

Use short imperative subjects, for example:

```text
Classify recent-input locks as manual away
```

By participating, you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
