part of '../routed_jobs.dart';

/// CLI command that evaluates configured schedules once.
///
/// The command is registered by [RoutedSchedulerProvider] in the engine's
/// application command registry. A Routed CLI host discovers it after
/// bootstrapping the same engine used by the server.
final class RoutedJobsScheduleCommand extends Command<void> {
  /// Creates a schedule command for [scheduler].
  RoutedJobsScheduleCommand(this.scheduler);

  /// Scheduler to evaluate.
  final RoutedScheduler scheduler;

  @override
  String get name => 'schedule';

  @override
  List<String> get aliases => const ['schedule:run'];

  @override
  String get description => 'Run due application schedules once.';

  @override
  String get summary => 'Evaluate schedules and dispatch due jobs.';

  @override
  String get category => 'Scheduling';

  @override
  Future<void> run() async {
    final report = await scheduler.tick();
    writeRoutedCommandLine(
      this,
      'Schedule tick completed: '
      'considered=${report.considered}, '
      'claimed=${report.claimed}, '
      'completed=${report.completed}, '
      'skipped=${report.skipped}',
    );
  }
}

/// CLI command that keeps the scheduler running in a normal Routed process.
///
/// Platform-triggered runtimes such as Cloudflare should call the one-shot
/// [RoutedScheduler.tick] bridge instead; this command is for a worker process
/// that can own a timer for its lifetime.
final class RoutedJobsScheduleWorkCommand extends Command<void> {
  /// Creates a schedule worker command for [scheduler].
  RoutedJobsScheduleWorkCommand(this.scheduler);

  /// Scheduler to run.
  final RoutedScheduler scheduler;

  @override
  String get name => 'schedule:work';

  @override
  List<String> get aliases => const ['schedule:listen'];

  @override
  String get description => 'Run application schedules continuously.';

  @override
  String get summary => 'Keep the scheduler worker alive.';

  @override
  String get category => 'Scheduling';

  @override
  Future<void> run() => scheduler.work();
}
