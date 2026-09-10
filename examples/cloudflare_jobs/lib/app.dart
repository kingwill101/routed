import 'dart:convert';

import 'package:routed/routed.dart';
import 'package:routed_node/cloudflare.dart';

/// A small durable job used by the live Worker validation.
JobDefinition<String, String> resultJob(CloudflareEnvironment environment) {
  return JobDefinition<String, String>(
    name: 'demo.record-result',
    encode: (value) => {'value': value},
    decode: (payload) => payload['value']! as String,
    options: const JobOptions(maxAttempts: 3),
    handle: (context, value) async {
      final result = <String, Object?>{
        'jobId': context.id,
        'attempt': context.attempt,
        'value': value,
        'processedAt': DateTime.now().toUtc().toIso8601String(),
      };
      await environment.kv('RESULTS').put('last', jsonEncode(result));
      await environment
          .kv('RESULTS')
          .put('job:${context.id}', jsonEncode(result));
      return value;
    },
  );
}

RoutedJobs createJobs(
  CloudflareEnvironment environment, {
  JobDefinition<String, String>? definition,
}) {
  final queue = CloudflareJobQueue(environment.queue('JOBS'));
  return RoutedJobs(
    queue: queue,
    definitions: [definition ?? resultJob(environment)],
  );
}

/// Durable Object class used by the scheduler's occurrence ledger.
final class CloudflareScheduleStoreObject
    extends CloudflareDurableObjectStoreObject {
  CloudflareScheduleStoreObject(super.state, super.env);
}

/// Creates the environment-backed HTTP Worker engine.
Future<Engine> createCloudflareEngine(CloudflareEnvironment environment) async {
  final definition = resultJob(environment);
  final jobs = createJobs(environment, definition: definition);
  final engine = Engine(
    providers: Engine.defaultProviders,
    options: [withJobs(jobs)],
  );

  engine.get('/', (context) {
    return context.json({
      'service': 'routed-cloudflare-jobs-example',
      'runtime': 'cloudflare',
      'routes': {
        'dispatch': 'POST /dispatch?value=hello',
        'result': 'GET /result',
        'health': 'GET /health',
      },
    });
  });

  engine.get('/health', (context) async {
    final environment = cloudflareEnvironmentOf(context);
    if (environment == null) {
      return context.json({
        'ok': false,
        'error': 'environment_unavailable',
      }, statusCode: 500);
    }
    final metrics = await environment.queue('JOBS').metrics();
    return context.json({
      'ok': true,
      'queue': metrics.backlogCount,
      'last': await environment.kv('RESULTS').get('last'),
    });
  });

  engine.post('/dispatch', (context) async {
    final value = context.request.queryParameters['value'] ?? 'hello';
    final receipt = await context.jobs.dispatch(definition, value);
    return context.json({
      'queued': true,
      'id': receipt.id,
      'name': receipt.name,
      'value': value,
    }, statusCode: 202);
  });

  engine.get('/result', (context) async {
    final environment = cloudflareEnvironmentOf(context);
    if (environment == null) {
      return context.json({
        'ok': false,
        'error': 'environment_unavailable',
      }, statusCode: 500);
    }
    final raw = await environment.kv('RESULTS').get('last');
    return context.json({'processed': raw == null ? null : jsonDecode(raw)});
  });

  await engine.initialize();
  return engine;
}

/// Factory consumed by the Cloudflare Queue event bridge.
Future<JobConsumer> createCloudflareJobConsumer(
  CloudflareEnvironment environment,
) async => createJobs(environment);

/// Creates the application scheduler from the Worker environment.
Future<RoutedScheduler> createCloudflareScheduler(
  CloudflareEnvironment environment,
) async {
  final definition = resultJob(environment);
  final jobs = createJobs(environment, definition: definition);
  final store = CloudflareScheduleStore(
    store: CloudflareDurableObjectStore(
      namespace: environment.durableObjectNamespace('SCHEDULE_STORE'),
      objectPrefix: 'routed-cloudflare-jobs-schedule',
    ),
  );
  return RoutedScheduler(
    dispatcher: jobs,
    store: store,
    // Cloudflare wakes this Worker every minute; the scheduler looks back
    // far enough to recover a missed tick without creating duplicate runs.
    lookback: const Duration(minutes: 2),
    claimLease: const Duration(minutes: 2),
    schedules: [
      ScheduleDefinition.job(
        name: 'demo.record-result.every-five-minutes',
        frequency: ScheduleFrequency.every(const Duration(minutes: 5)),
        job: definition,
        args: 'cron',
        maxCatchUp: 2,
      ),
    ],
  );
}
