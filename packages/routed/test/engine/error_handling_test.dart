import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('Engine error hooks', () {
    const teapotStatus = 418;

    test('custom handler can replace default error response', () async {
      final engine = testEngine();
      final events = <String>[];

      engine.beforeError((ctx, error, stack) {
        events.add('before:${error.runtimeType}');
      });

      engine.afterError((ctx, error, stack) {
        events.add('after:${ctx.response.statusCode}');
      });

      engine.onError<StateError>((ctx, error, stack) {
        ctx.json({'message': error.message}, statusCode: teapotStatus);
        return true;
      });

      engine.get('/boom', (ctx) async {
        throw StateError('boom');
      });

      final client = TestClient(RoutedRequestHandler(engine));
      final response = await client.get('/boom');
      response.assertStatus(teapotStatus);
      expect(await response.json(), {'message': 'boom'});

      expect(events.first, 'before:StateError');
      expect(events.last, 'after:$teapotStatus');

      await client.close();
    });

    test('observers fire when default handlers run', () async {
      final engine = testEngine();
      final events = <String>[];

      engine.beforeError((ctx, error, stack) {
        events.add('before:${error.runtimeType}');
      });

      engine.afterError((ctx, error, stack) {
        events.add('after:${ctx.response.statusCode}');
      });

      engine.get('/invalid', (ctx) async {
        throw ValidationError({
          'name': ['required'],
        });
      });

      final client = TestClient(RoutedRequestHandler(engine));
      final response = await client.get(
        '/invalid',
        headers: {
          'Accept': ['application/json'],
        },
      );
      response.assertStatus(HttpStatus.unprocessableEntity);
      final payload = await response.json() as Map<String, dynamic>;
      expect(payload['name'], contains('required'));

      expect(
        events.any((event) => event.startsWith('before:ValidationError')),
        isTrue,
      );
      expect(events.any((event) => event == 'after:422'), isTrue);

      await client.close();
    });
  });
}
