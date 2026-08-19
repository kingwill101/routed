import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

class TestService {
  TestService(this.value);

  final String value;
}

class LifecycleProvider extends ServiceProvider {
  LifecycleProvider(this.value);

  final String value;
  int registerCalls = 0;
  int bootCalls = 0;
  int cleanupCalls = 0;

  @override
  void register(Container container) {
    registerCalls++;
    container.singleton<TestService>((_) async => TestService(value));
  }

  @override
  Future<void> boot(Container container) async => bootCalls++;

  @override
  Future<void> cleanup(Container container) async => cleanupCalls++;
}

void main() {
  engineGroup(
    'ContainerMixin via Engine',
    options: [
      (Engine engine) {
        final provider = LifecycleProvider('from-provider');
        engine.registerProvider(provider);

        engine.get('/scoped', (ctx) async {
          final service = await ctx.container.make<TestService>();
          final rawRequest = await ctx.container.make<HttpRequest>();
          // ignore: close_sinks
          final rawResponse = await ctx.container.make<HttpResponse>();
          return ctx.json({
            'service': service.value,
            'rawRequestType': rawRequest.runtimeType.toString(),
            'ctxRequestType': ctx.request.httpRequest.runtimeType.toString(),
            'requestSharesResponse': identical(
              rawRequest.response,
              ctx.request.httpRequest.response,
            ),
            'responseType': rawResponse.runtimeType.toString(),
            'configType': ctx.config<EngineConfig>().runtimeType.toString(),
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
      });

      engineTest('request containers inherit typed configuration', (
        Engine engine,
        TestClient client,
      ) async {
        final response = await client.get('/scoped');
        response.assertStatus(200);
        expect(response.json('service'), equals('from-provider'));
        expect(response.json('configType'), contains('EngineConfig'));
        expect(response.json('requestSharesResponse'), isTrue);
      });

      engineTest('bootProviders is idempotent', (
        Engine engine,
        TestClient client,
      ) async {
        await engine.bootProviders();
        await engine.bootProviders();
        expect(engine.unresolvedProviderDependencies, isEmpty);
      });
    },
  );
}
