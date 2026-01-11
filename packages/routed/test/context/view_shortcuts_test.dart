import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('requireFound', () {
    test('returns value when present', () async {
      final engine = testEngine();
      engine.get('/present', (ctx) {
        final result = ctx.requireFound<int>(42);
        return ctx.json({'value': result, 'errors': ctx.errors.length});
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get('/present');
      expect(response.json()['value'], equals(42));
      expect(response.json()['errors'], equals(0));
    });

    test('throws NotFoundError and records error when null', () async {
      final engine = testEngine();
      engine.get('/missing', (ctx) {
        try {
          ctx.requireFound<Object?>(null, message: 'user missing');
          return ctx.json({'error': 'none'});
        } catch (error) {
          if (error is NotFoundError) {
            return ctx.json({
              'message': error.message,
              'errors': ctx.errors.length,
            });
          }
          rethrow;
        }
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get('/missing');
      expect(response.json()['errors'], equals(1));
      expect(response.json()['message'], equals('user missing'));
    });
  });

  group('fetchOr404', () {
    test('awaits callback and returns value', () async {
      final engine = testEngine();
      engine.get('/fetch', (ctx) async {
        final result = await ctx.fetchOr404(() async => 'item');
        return ctx.json({'value': result, 'errors': ctx.errors.length});
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get('/fetch');
      expect(response.json()['value'], equals('item'));
      expect(response.json()['errors'], equals(0));
    });

    test('awaits callback and throws NotFoundError', () async {
      final engine = testEngine();
      engine.get('/fetch-missing', (ctx) async {
        try {
          await ctx.fetchOr404(() async => null, message: 'not here');
          return ctx.json({'error': 'none'});
        } catch (error) {
          if (error is NotFoundError) {
            return ctx.json({
              'message': error.message,
              'errors': ctx.errors.length,
            });
          }
          rethrow;
        }
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get('/fetch-missing');
      expect(response.json()['errors'], equals(1));
      expect(response.json()['message'], equals('not here'));
    });
  });
}
