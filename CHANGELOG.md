# Changelog

## 0.6.0 — 2026-11-07

- Remembered Day/Week navigation and weekly List/Calendar layouts, with a
  compact hourly grid, overlapping activities, and a current-time indicator.
- Read-only Canvas academic panel with assignments, announcements, courses,
  published grades, materials, and optional calendar deadlines/events.
- Independent resource caches, offline fallback, lazy loading, and bounded
  concurrent Canvas requests.
- Interactive desktop widget with activity progress/countdowns, upcoming
  activities, prioritized deadlines, weekly workload, and persistent
  compact/expanded layouts. Drag it by its header.
- Desktop text and accents inherit the bar theme; its background and border
  follow the popup theme dynamically.
- Animated popup, labeled view selectors, and compact CSV import control.
- Lower background work through debounced file watching, prepared timestamps,
  stable card models, and unloading hidden desktop content.
- Isolated stress-test CPU reduced by about 87%; starting hidden saved about
  11 MiB of private memory. See [measurement conditions](docs/performance.md).

### Update

```bash
omarchy plugin update io.github.javihuh.schedule --yes
```
