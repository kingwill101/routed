# routed_jobs

Laravel-inspired jobs and queue primitives for Routed applications.

`routed_jobs` owns the application-facing contract. A queue adapter only needs
to implement `JobQueue`, while Routed keeps the portable execution and retry
pipeline behind `RoutedJobs`. Stem is an internal implementation detail and is
not part of the public API.

```dart
import 'package:routed_jobs/routed_jobs.dart';

final sendWelcome = JobDefinition<String, String>(
  name: 'mail.welcome',
  encode: (email) => {'email': email},
  decode: (payload) => payload['email']! as String,
  options: const JobOptions(maxAttempts: 3),
  handle: (context, email) async {
    // Send the message here.
    return email;
  },
);

final jobs = RoutedJobs(
  queue: myQueue,
  definitions: [sendWelcome],
);

final receipt = await jobs.dispatch(sendWelcome, 'person@example.com');
```

Consumers receive a `JobMessage` from their host runtime and pass it to
`RoutedJobs.process`. A retry result contains the next message and delay; a
terminal failure can be sent to the host's dead-letter handling.

For an engine-owned instance, use `RoutedJobsProvider` or `withJobs`. Request
handlers can then use `ctx.jobs` without knowing the queue implementation.

## Scheduling

`RoutedScheduler` evaluates application schedules and dispatches ordinary
Routed jobs. Platform cron is only a wake-up signal; the occurrence store
prevents duplicate dispatch when multiple runtimes receive the same tick.

```dart
final scheduler = RoutedScheduler(
  dispatcher: jobs,
  store: InMemoryScheduleStore(), // use a durable adapter in production
  schedules: [
    ScheduleDefinition.job(
      name: 'reports.every-five-minutes',
      frequency: ScheduleFrequency.every(const Duration(minutes: 5)),
      job: sendWelcome,
      args: 'person@example.com',
    ),
  ],
);

await scheduler.tick();
```

Convenience frequencies include `everyMinute`, `hourly`, `dailyAt`, and
`weeklyOn`; arbitrary five-field UTC cron expressions are also supported.
`CloudflareScheduleStore` in `routed_node` can use an atomic
`CloudflareDurableObjectStore` for a Worker-safe occurrence ledger. Schedule
definitions remain code-owned; a database-backed definition repository can be
layered on the same `ScheduleStore` contract when schedules must be edited at
runtime.

For a normal long-lived Routed process, use the Beat-backed worker command:

```shell
dart run routed_cli:routed schedule:work
```

The worker keeps the process alive and uses Stem's scheduler loop internally;
Stem types are not part of the Routed API. Cloudflare and other event-driven
hosts should continue using the one-shot `schedule`/`schedule:run` command or
the runtime-specific scheduled-event bridge.

When the scheduler is installed with `RoutedSchedulerProvider`, the provider
also registers the one-shot `schedule` command (aliased as `schedule:run`) and
the long-running `schedule:work` command on the application engine. The Routed
CLI discovers these commands from the same provider composition used by the
server, so no command registration is needed in `routed_cli` or in application
glue code.

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_jobs/routed_jobs.dart';

final engine = await Engine.create(
  providers: [RoutedJobsProvider(), RoutedSchedulerProvider()],
);
```

With that composition, `dart run routed_cli:routed schedule` evaluates the
configured schedules once and exits.
