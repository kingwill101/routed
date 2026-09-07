## Unreleased

- Failed Stem-backed schedule occurrences remain due for retry, and scheduler
  provider cleanup is limited to the root engine container.

- `RoutedScheduler` now exposes `start`, `stop`, `runOnce`, and `work`; the
  long-running path uses Stem Beat internally and the provider registers
  `schedule:work`/`schedule:listen`.
- `RoutedSchedulerProvider` now contributes a `schedule`/`schedule:run` command
  to the application engine's CLI registry.
- Jobs CLI commands now use Routed's Artisanal argument abstraction rather
  than depending directly on `package:args`.

## 0.1.0

- Initial Laravel-inspired jobs and queue API for Routed.
- Add typed job definitions, dispatch options, queue messages, and processing
  outcomes without exposing Stem to application code.
- Add `RoutedJobsProvider`, `withJobs`, and `EngineContext.jobs` integration.
- Add portable schedule frequencies, occurrence leasing, scheduler providers,
  and idempotent scheduled job dispatch.
