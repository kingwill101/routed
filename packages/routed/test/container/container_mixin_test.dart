import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

class TestService {
  final String value;

  TestService(this.value);
}

class LifecycleProvider extends ServiceProvider {
  final String value;
  int registerCalls = 0;
  int bootCalls = 0;
  int cleanupCalls = 0;

  LifecycleProvider(this.value);

  @override
  void register(Container container) {
    registerCalls++;
    container.singleton<TestService>((_) async => TestService(value));
  }

  @override
  Future<void> boot(Container container) async {
    bootCalls++;
  }

  @override
  Future<void> cleanup(Container container) async {
    cleanupCalls++;
  }
}

void main() {
  late LifecycleProvider lifecycleProvider;

  engineGroup(
    'ContainerMixin via Engine',
    options: [
      (Engine engine) {
        lifecycleProvider = LifecycleProvider('from-provider');
        engine.registerProvider(lifecycleProvider);

        engine.get('/scoped', (ctx) async {
          final service = await ctx.container.make<TestService>();
          final rawRequest = await ctx.container.make<HttpRequest>();
          // ignore: close_sinks
          final rawResponse = await ctx.container.make<HttpResponse>();

          final sharesResponse = identical(
            rawRequest.response,
            ctx.request.httpRequest.response,
          );

          return ctx.json({
            'service': service.value,
            'rawRequestType': rawRequest.runtimeType.toString(),
            'ctxRequestType': ctx.request.httpRequest.runtimeType.toString(),
            'requestSharesResponse': sharesResponse,
            'responseType': rawResponse.runtimeType.toString(),
          });
        });

        engine.get('/mutate-config', (ctx) async {
          final scopedConfig = await ctx.container.make<Config>();
          scopedConfig.set('request.only', 'scoped');

          final rootConfig = ctx.engine?.appConfig;
          final isSameAsRoot =
              rootConfig != null && identical(scopedConfig, rootConfig);

          return ctx.json({
            'requestOnly': scopedConfig.get<String>('request.only'),
            'zoneAppName': Config.current.get<String>('app.name'),
            'isSameAsRoot': isSameAsRoot,
          });
        });
      },
    ],
    define: (engine, client, engineTest) {
      engineTest('registerProvider registers services immediately', (
        Engine engine,
        TestClient client,
      ) async {
        final service = await engine.make<TestService>();
        expect(service.value, equals('from-provider'));
        expect(lifecycleProvider.registerCalls, equals(1));
      });

      engineTest('bootProviders runs once even when called multiple times', (
        Engine engine,
        TestClient client,
      ) async {
        expect(lifecycleProvider.bootCalls, equals(0));
        await engine.bootProviders();
        await engine.bootProviders();
        expect(lifecycleProvider.bootCalls, equals(1));
      });

      engineTest(
        'providers registered after boot run their boot hook immediately',
        (Engine engine, TestClient client) async {
          await engine.bootProviders();

          final lateProvider = LifecycleProvider('late-register');
          engine.registerProvider(lateProvider);

          expect(lateProvider.registerCalls, equals(1));
          expect(lateProvider.bootCalls, equals(1));
        },
      );

      engineTest('cleanupRequestContainer delegates cleanup to providers', (
        Engine engine,
        TestClient client,
      ) async {
        final cleanupProbe = LifecycleProvider('cleanup-probe');
        engine.registerProvider(cleanupProbe);

        await engine.cleanupRequestContainer(engine.container);

        expect(cleanupProbe.cleanupCalls, equals(1));
      });

      engineTest(
        'request containers inherit bindings and expose request instances',
        (Engine engine, TestClient client) async {
          final response = await client.get('/scoped');
          response.assertStatus(200).assertHasHeader('Content-Type');

          final body = response.jsonBody as Map<String, dynamic>;
          expect(body['service'], equals('from-provider'));
          expect(body['rawRequestType'], equals('MockHttpRequest'));
          expect(body['ctxRequestType'], contains('WrappedRequest'));
          expect(body['requestSharesResponse'], isTrue);
          expect(body['responseType'], contains('MockHttpResponse'));
        },
      );

      engineTest('request config mutations remain scoped to the request', (
        Engine engine,
        TestClient client,
      ) async {
        final rootConfig = await engine.make<Config>();
        expect(rootConfig.has('request.only'), isFalse);

        final response = await client.get('/mutate-config');
        response.assertStatus(200);

        expect(response.json('requestOnly'), equals('scoped'));
        expect(response.json('zoneAppName'), equals('Test App'));
        expect(response.json('isSameAsRoot'), isFalse);

        final postRequestConfig = await engine.make<Config>();
        expect(postRequestConfig.has('request.only'), isFalse);
      });

      engineTest('Config.runWith temporarily overrides zone configuration', (
        Engine engine,
        TestClient client,
      ) async {
        final original = await engine.make<Config>();
        expect(Config.current, same(original));

        final override = ConfigImpl({
          'app.name': 'Override App',
          'app.env': 'testing',
        });

        await Config.runWith(override, () async {
          expect(Config.current, same(override));
          final resolved = await engine.make<Config>();
          expect(identical(resolved, override), isTrue);
        });

        final restored = await engine.make<Config>();
        expect(restored, same(original));
        expect(Config.current, same(original));
      });
    },
  );
}
