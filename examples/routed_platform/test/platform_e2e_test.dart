import 'package:routed_platform/app.dart' as app;
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  test('submits an authenticated task and returns its Stem result', () async {
    final engine = await app.createEngine();
    final client = TestClient(RoutedRequestHandler(engine));

    final submit = await client.postJson(
      '/v1/tasks',
      {'message': 'hello'},
      headers: {
        'authorization': ['Bearer demo-token'],
        'idempotency-key': ['test-task-1'],
      },
    );
    submit.assertStatus(202);
    final taskId = (submit.json() as Map<String, dynamic>)['taskId'] as String;

    final repeat = await client.postJson(
      '/v1/tasks',
      {'message': 'hello'},
      headers: {
        'authorization': ['Bearer demo-token'],
        'idempotency-key': ['test-task-1'],
      },
    );
    repeat.assertStatus(202);
    expect((repeat.json() as Map<String, dynamic>)['taskId'], taskId);

    final conflict = await client.postJson(
      '/v1/tasks',
      {'message': 'different payload'},
      headers: {
        'authorization': ['Bearer demo-token'],
        'idempotency-key': ['test-task-1'],
      },
    );
    conflict.assertStatus(409);

    final status = await client.get(
      '/v1/tasks/$taskId',
      headers: {
        'authorization': ['Bearer demo-token'],
      },
    );
    status.assertStatus(200);
    final payload = status.json() as Map<String, dynamic>;
    expect(payload['state'], anyOf('queued', 'running', 'succeeded'));

    await client.close();
    await engine.close();
  });

  test('requires authentication and idempotency keys', () async {
    final engine = await app.createEngine();
    final client = TestClient(RoutedRequestHandler(engine));

    final unauthorized = await client.postJson('/v1/tasks', {'message': 'x'});
    unauthorized.assertStatus(401);

    final missingKey = await client.postJson(
      '/v1/tasks',
      {'message': 'x'},
      headers: {
        'authorization': ['Bearer demo-token'],
      },
    );
    missingKey.assertStatus(400);

    await client.close();
    await engine.close();
  });
}
