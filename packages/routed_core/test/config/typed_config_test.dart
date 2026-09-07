import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigStore', () {
    test('resolves provider-owned configuration by type', () {
      final provider = _TestProvider(const _TestConfig(port: 8080));

      final store = ConfigStore.fromProviders([provider]);

      expect(store.get<_TestConfig>().port, 8080);
      expect(store.contains<_TestConfig>(), isTrue);
    });

    test('aggregates validation failures before boot', () {
      final provider = _TestProvider(const _TestConfig(port: 0));

      expect(
        () => ConfigStore.fromProviders([provider]),
        throwsA(
          isA<ConfigValidationException>().having(
            (error) => error.issues.single.toString(),
            'issue',
            contains('port must be greater than zero'),
          ),
        ),
      );
    });

    test('rejects duplicate configuration types', () {
      final providers = [
        _TestProvider(const _TestConfig(port: 8080)),
        _TestProvider(const _TestConfig(port: 9090)),
      ];

      expect(
        () => ConfigStore.fromProviders(providers),
        throwsA(isA<StateError>()),
      );
    });

    test('engine publishes typed configuration after provider boot', () async {
      final engine = Engine(
        providers: [_TestProvider(const _TestConfig(port: 8080))],
      );
      addTearDown(engine.close);

      await engine.initialize();

      expect(engine.typedConfig<_TestConfig>().port, 8080);
      expect(engine.container.get<ConfigStore>().get<_TestConfig>().port, 8080);
    });
  });

  group('RuntimeContext', () {
    test('parses typed environment values', () {
      final runtime = RuntimeContext(
        environment: RuntimeEnvironment(
          {'PORT': '8080', 'DEBUG': 'yes'},
          arguments: const ['serve'],
          isWindows: true,
        ),
        secrets: RuntimeSecrets({'TOKEN': 'private'}),
      );

      expect(runtime.environment.requiredInteger('PORT'), 8080);
      expect(runtime.environment.boolean('DEBUG'), isTrue);
      expect(runtime.environment.arguments, ['serve']);
      expect(runtime.environment.isWindows, isTrue);
      expect(runtime.secrets.requiredString('TOKEN'), 'private');
    });

    test('can snapshot an environment supplied by a host adapter', () {
      final runtime = RuntimeContext(
        environmentSource: _TestEnvironmentSource(),
      );

      expect(runtime.environment.string('APP_ENV'), 'test');
      expect(runtime.environment.arguments, ['check']);
    });

    test('does not expose secret values in the secret object string', () {
      final runtime = RuntimeSecrets({'TOKEN': 'private'});

      expect(runtime.toString(), isNot(contains('private')));
    });
  });
}

class _TestConfig implements ValidatableConfiguration {
  const _TestConfig({required this.port});

  final int port;

  @override
  void validate(ConfigValidationContext context) {
    context.require(port > 0, 'port', 'port must be greater than zero');
  }
}

final class _TestEnvironmentSource implements RuntimeEnvironmentSource {
  @override
  RuntimeEnvironment snapshot() => RuntimeEnvironment(
    {'APP_ENV': 'test'},
    arguments: const ['check'],
  );
}

class _TestProvider extends ServiceProvider
    with ProvidesTypedConfiguration<_TestConfig> {
  _TestProvider(this.configuration);

  @override
  final _TestConfig configuration;

  @override
  void register(Container container) {}
}
