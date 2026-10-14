# Privacy

WorkRhythm is designed as a local-first application.

## Data collected locally

- Workstation state boundaries and timestamps
- Focus sessions and effective focus segments
- Hydration records, selected drink type and volume
- User settings, labels and reminders
- Limited diagnostic events required to explain state classification

All application data is stored in the user's Application Support directory. WorkRhythm does not include a server, telemetry SDK, advertising SDK or crash-reporting service.

## System signals used

- macOS lock, unlock, display sleep/wake and system sleep/wake notifications
- Aggregate seconds since the last input event
- Mouse position near configured Hot Corners
- Display geometry and lid state

WorkRhythm does not read key values or typed text. It does not capture screenshots, inspect foreground application contents, read browser history, access the clipboard or store a continuous mouse trail.

## Network access

The application does not initiate network requests. Building the project may use GitHub and Apple developer tools, but the running application has no network feature.

## Retention and deletion

Work and hydration history remain until the user deletes the local database. Diagnostic events are pruned after 30 days. To remove all data:

1. Quit WorkRhythm.
2. Delete `~/Library/Application Support/WorkRhythm`.
3. Optionally remove WorkRhythm from Login Items and delete the application.

## Exports

CSV, database backups and diagnostic JSON are created only after a user action. Exports may reveal working hours, breaks and diagnostic coordinates. Review them before sharing.

## Permissions

Notification permission is optional. WorkRhythm does not request Accessibility, Input Monitoring, Screen Recording or Automation permission.

## Questions

Open a GitHub issue for privacy questions that do not contain personal data. Use the private security reporting route described in [SECURITY.md](SECURITY.md) for sensitive reports.
