# Desktop widget performance

Measured locally on 2026-11-07, before and after the desktop performance pass.
The baseline already includes the new progress, priorities, weekly summary,
and compact/expanded features; this compares the same features before/after
avoiding unnecessary work.

## Method

- A separate Quickshell process per case, Qt 6.12, offscreen software rendering.
- No screenshots, Canvas requests, real credentials, or schedule helper calls.
- Four seconds of warm-up before sampling.
- Normal data: 30 scheduled occurrences and 30 Canvas assignments. Visible
  cases sampled for 31 seconds with the normal 30-second clock; hidden and
  disabled cases sampled for eight seconds.
- Stress data: 1,000 occurrences and 1,000 assignments, advancing the clock
  every second for 12 seconds. This is deliberately more demanding than normal
  operation.
- CPU: Linux `/proc/PID/stat`, expressed as a percentage of **one CPU core**.
- Memory: median private clean + dirty memory from `/proc/PID/smaps_rollup`.
  Values include the isolated Qt/Quickshell runtime, not just widget objects.
  The real desktop shares that runtime with the other shell plugins.
- Each hidden case starts hidden. Repeated loading/unloading was checked
  separately, because a process may retain compiled QML and allocator caches.

## Results

| Case | CPU before | CPU after | Private memory before | Private memory after |
| --- | ---: | ---: | ---: | ---: |
| No widget | 0.000% | 0.000% | 67.20 MiB | 69.21 MiB |
| Starts hidden | 0.000% | 0.000% | 78.89 MiB | 68.18 MiB |
| Compact, normal data | 0.064% | 0.096% | 84.13 MiB | 84.83 MiB |
| Expanded, normal data | 0.064% | 0.064% | 84.14 MiB | 84.00 MiB |
| Expanded, stress data | 8.543% | 1.078% | 91.20 MiB | 89.93 MiB |

Normal idle CPU was already very low and stayed below approximately 0.1% in
these samples; the small differences are at the resolution of a few CPU ticks.
Visible memory remained essentially unchanged. Under the accelerated stress
test, CPU time fell by about **87%**. Starting hidden avoided about **11 MiB**
of private memory in this isolated harness.

An additional test repeatedly loaded/unloaded the optimized component every
200 ms. Over the 15-second sample, median private memory was 86.19 MiB and RSS
ended 1.79 MiB below its initial sample rather than growing across the test.

## Changes responsible

- Unload desktop visual content when it is not visible; stop its clock too.
- Parse and sort activity/assignment timestamps only when their source data
  changes, instead of repeating this work on every clock tick.
- Preserve deadline models while order, state, and underlying data are unchanged.
  Countdown labels update without recreating the cards.
- Recalculate weekly workload only when data or the calendar day changes.
  Skip it entirely in compact mode.
- Keep following-activity models stable until the next activity changes.
- Watch schedule-file changes without preloading a second copy of its contents,
  with a 200 ms debounce and a five-minute fallback refresh. Opening the panel,
  manual refresh, and day rollover also update the snapshot.
- Periodic schedule expansions drop from 120/hour to 12/hour while visible,
  excluding explicit actions/file changes. Reminder checks still run every
  30 seconds and use the existing backend.

The data/model tests cover clock transitions, priorities, and stable models.
Runtime checks also verified compact/expanded layout changes, reuse across
clock ticks, and detection of consecutive atomic schedule-file replacements.
