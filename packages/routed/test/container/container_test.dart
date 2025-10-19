import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/config/config.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/view/engine_manager.dart';
import 'package:test/test.dart';

abstract class ServiceInterface {
  String get value;
}

class ServiceImplementation implements ServiceInterface {
  @override
  final String value;

  ServiceImplementation(this.value);
}

class TestService {
  final String value;

  TestService(this.value);
}

class DependentService {
  final TestService testService;

  DependentService(this.testService);
}

class CountingProvider extends ServiceProvider {
  int registerCount = 0;
  int bootCount = 0;

  @override
  void register(Container container) {
    registerCount++;
  }

  @override
  Future<void> boot(Container container) async {
    bootCount++;
  }
}

void main() {
  group('Container', () {
    late Container container;

    setUp(() {
      container = Container();
    });

    test('bind and make instance', () async {
      container.bind<TestService>(
        (c) async => TestService('test'),
        singleton: false,
      );
      final service = await container.make<TestService>();
      expect(service, isA<TestService>());
      expect(service.value, equals('test'));
    });

    test('singleton returns same instance', () async {
      container.bind<TestService>(
        (c) async => TestService('test'),
        singleton: true,
      );
      final service1 = await container.make<TestService>();
      final service2 = await container.make<TestService>();
      expect(identical(service1, service2), isTrue);
    });

    test('transient returns different instances', () async {
      container.bind<TestService>(
        (c) async => TestService('test'),
        singleton: false,
      );
      final service1 = await container.make<TestService>();
      final service2 = await container.make<TestService>();
      expect(identical(service1, service2), isFalse);
    });

    test('instance binding returns same instance', () async {
      final instance = TestService('test');
      container.instance<TestService>(instance);
      final resolved = await container.make<TestService>();
      expect(identical(instance, resolved), isTrue);
    });

    test('alias binds one type to another', () async {
      container.bind<ServiceImplementation>(
        (c) async => ServiceImplementation('test'),
        singleton: true,
      );
      container.alias<ServiceInterface, ServiceImplementation>();
      final service = await container.make<ServiceInterface>();
      expect(service, isA<ServiceImplementation>());
      expect(service.value, equals('test'));
    });

    test('child container inherits parent bindings', () async {
      container.bind<TestService>(
        (c) async => TestService('parent'),
        singleton: true,
      );
      final child = container.createChild();
      final service = await child.make<TestService>();
      expect(service.value, equals('parent'));
    });

    test('child container can override parent bindings', () async {
      container.bind<TestService>(
        (c) async => TestService('parent'),
        singleton: true,
      );
      final child = container.createChild();
      child.bind<TestService>(
        (c) async => TestService('child'),
        singleton: true,
      );
      final service = await child.make<TestService>();
      expect(service.value, equals('child'));
    });

    test('has returns true for registered bindings', () {
      container.bind<TestService>((c) async => TestService('test'));
      expect(container.has<TestService>(), isTrue);
      expect(container.has<DependentService>(), isFalse);
    });

    test('throws when resolving unregistered type', () async {
      expect(() => container.make<TestService>(), throwsStateError);
    });

    test('async dependencies are resolved', () async {
      container.bind<TestService>((c) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return TestService('async');
      });

      final service = await container.make<TestService>();
      expect(service.value, equals('async'));
    });

    test('makeAll resolves multiple dependencies', () async {
      container.bind<TestService>(
        (c) async => TestService('1'),
        singleton: false,
      );
      container.bind<DependentService>(
        (c) async => DependentService(await c.make<TestService>()),
      );

      final results = await container.makeAll([TestService, DependentService]);
      expect(results[0], isA<TestService>());
      expect(results[1], isA<DependentService>());
    });
  });

  group('Container Tests', () {
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
      expect(config.get('app.name'), equals('Test App'));
      expect(config.get('app.env'), equals('testing'));
      expect(config.get('custom.key'), equals('custom value'));

      // Test ConfigImpl concrete binding
      final configImpl = await engine.make<Config>();
      expect(configImpl, isNotNull);
      expect(configImpl.get('app.name'), equals('Test App'));

      // Verify it's the same instance
      expect(configImpl, equals(config));
    });

    test('Config is mutable through container', () async {
      final config = await engine.make<Config>();

      // Test setting new values
      config.set('new.key', 'new value');
      expect(config.get('new.key'), equals('new value'));

      // Verify changes are reflected in subsequent resolutions
      final anotherConfig = await engine.make<Config>();
      expect(anotherConfig.get('new.key'), equals('new value'));
    });

    test('Config array operations work correctly', () async {
      final config = await engine.make<Config>();

      // Test push operation
      config.push('test.array', 'first');
      config.push('test.array', 'second');
      expect(config.get('test.array'), equals(['first', 'second']));

      // Test prepend operation
      config.prepend('test.array', 'zero');
      expect(config.get('test.array'), equals(['zero', 'first', 'second']));
    });

    test('bootProviders boots custom providers only once', () async {
      final provider = CountingProvider();
      engine.registerProvider(provider);

      await engine.bootProviders();
      await engine.bootProviders();

      expect(provider.registerCount, equals(1));
      expect(provider.bootCount, equals(1));
    });
  });

  group('Container Advanced Features', () {
    late Container container;

    setUp(() {
      container = Container();
    });

    test('singleton shorthand creates shared instance', () async {
      container.singleton<TestService>((c) async => TestService('singleton'));
      final first = await container.make<TestService>();
      final second = await container.make<TestService>();
      expect(identical(first, second), isTrue);
      expect(first.value, equals('singleton'));
    });

    test('scoped bindings are cleared properly', () async {
      container.scoped<TestService>((c) async => TestService('scoped'));
      final first = await container.make<TestService>();
      expect(first.value, equals('scoped'));

      container.clearScoped();
      expect(() => container.make<TestService>(), throwsStateError);
    });

    test('contextual bindings work correctly', () async {
      container.bind<TestService>((c) async => TestService('default'));
      container.addContextualBinding(
        DependentService,
        TestService,
        (Container c) async => TestService('contextual'),
      );

      final defaultService = await container.make<TestService>();
      expect(defaultService.value, equals('default'));

      final contextual = await container.make<TestService>();
      expect(
        contextual.value,
        equals('default'),
      ); // No context, so default binding
    });

    test('resolving callbacks are executed', () async {
      var callbackExecuted = false;
      container.bind<TestService>((c) async => TestService('test'));

      container.resolving<TestService>((instance, container) {
        callbackExecuted = true;
        expect(instance, isA<TestService>());
      });

      await container.make<TestService>();
      expect(callbackExecuted, isTrue);
    });

    test('after resolving callbacks are executed', () async {
      var callbackExecuted = false;
      container.bind<TestService>((c) async => TestService('test'));

      container.afterResolving<TestService>((instance, container) {
        callbackExecuted = true;
        expect(instance, isA<TestService>());
      });

      await container.make<TestService>();
      expect(callbackExecuted, isTrue);
    });

    test('has method checks all binding types', () {
      // Test regular binding
      container.bind<TestService>((c) async => TestService('test'));
      expect(container.has<TestService>(), isTrue);

      // Test instance binding
      container.instance<DependentService>(
        DependentService(TestService('test')),
      );
      expect(container.has<DependentService>(), isTrue);

      // Test alias binding
      container.alias<ServiceInterface, ServiceImplementation>();
      expect(container.has<ServiceInterface>(), isTrue);

      // Test non-existent binding
      expect(container.has<String>(), isFalse);
    });

    test('multiple callbacks can be registered and executed', () async {
      var count = 0;
      container.bind<TestService>((c) async => TestService('test'));

      container.resolving<TestService>((instance, container) => count++);
      container.resolving<TestService>((instance, container) => count++);
      container.afterResolving<TestService>((instance, container) => count++);

      await container.make<TestService>();
      expect(count, equals(3));
    });
  });
}
