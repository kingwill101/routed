import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

void main() {
  test('caches EventManager absence after the first request', () async {
    final engine = Engine();
    engine.get('/', (ctx) => ctx.string('ok'));

    final client = TestClient.inMemory(RoutedRequestHandler(engine));
    addTearDown(() async {
      await client.close();
      await engine.close();
    });

    expect(engine.debugEventManagerChecked, isFalse);
    await client.get('/');
    expect(engine.debugEventManagerChecked, isTrue);
    await client.get('/');
    expect(engine.debugEventManagerChecked, isTrue);
  });

  test('logging gating respects config', () async {
    final engine = testEngine(configItems: const {'logging.enabled': false});
    await engine.initialize();
    addTearDown(() async {
      await engine.close();
    });

    expect(engine.debugIsLoggingEnabled(engine.container), isFalse);
    engine.container.get<Config>().set('logging.enabled', true);
    expect(engine.debugIsLoggingEnabled(engine.container), isTrue);
  });
}
