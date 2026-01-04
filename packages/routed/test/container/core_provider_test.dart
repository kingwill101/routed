import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('CoreServiceProvider Tests', () {
    late Engine engine;

    setUp(() async {
      engine = Engine(
        configItems: {
          'app.name': 'Test App',
          'app.env': 'testing',
          'custom.key': 'custom value',
        },
      );
      await engine.initialize();
    });

    test('Core services are automatically registered', () async {
      // Verify core services are available
      expect(await engine.make<Engine>(), isNotNull);
      expect(await engine.make<EngineConfig>(), isNotNull);
      expect(await engine.make<ViewEngineManager>(), isNotNull);
      expect(await engine.make<CacheManager>(), isNotNull);
    });

    test('Config is properly bound and accessible', () async {
      // Test Config interface binding
      final config = await engine.make<Config>();
      expect(config, isNotNull);
      expect(config.getOrThrow<String>('app.name'), equals('Test App'));
      expect(config.getOrThrow<String>('app.env'), equals('testing'));
      expect(config.getOrThrow<String>('custom.key'), equals('custom value'));

      // Test ConfigImpl concrete binding
      final configImpl = await engine.make<Config>();
      expect(configImpl, isNotNull);
      expect(configImpl.getOrThrow<String>('app.name'), equals('Test App'));

      // Verify it's the same instance
      expect(configImpl, equals(config));
    });

    test('Config is mutable through container', () async {
      final config = await engine.make<Config>();

      // Test setting new values
      config.set('new.key', 'new value');
      expect(config.getOrThrow<String>('new.key'), equals('new value'));

      // Verify changes are reflected in subsequent resolutions
      final anotherConfig = await engine.make<Config>();
      expect(anotherConfig.getOrThrow<String>('new.key'), equals('new value'));
    });

    test('Config array operations work correctly', () async {
      final config = await engine.make<Config>();

      // Test push operation
      config.push('test.array', 'first');
      config.push('test.array', 'second');
      expect(
        config.getStringListOrNull('test.array'),
        equals(['first', 'second']),
      );

      // Test prepend operation
      config.prepend('test.array', 'zero');
      expect(
        config.getStringListOrNull('test.array'),
        equals(['zero', 'first', 'second']),
      );
    });

    test('Services are singletons', () async {
      final engine1 = await engine.make<Engine>();
      final engine2 = await engine.make<Engine>();
      expect(identical(engine1, engine2), isTrue);

      final config1 = await engine.make<Config>();
      final config2 = await engine.make<Config>();
      expect(identical(config1, config2), isTrue);

      final configImpl1 = await engine.make<Config>();
      final configImpl2 = await engine.make<Config>();
      expect(identical(configImpl1, configImpl2), isTrue);
    });
  });
}
