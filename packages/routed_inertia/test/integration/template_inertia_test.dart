import 'package:file/memory.dart';
import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';
import 'package:routed_inertia/routed_inertia.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  group('Inertia template rendering', () {
    engineTest('uses view engine template when provided', (
      engine,
      client,
    ) async {
      final fs = MemoryFileSystem();
      engine.useViewEngine(
        LiquidViewEngine(root: LiquidRoot(fileSystem: fs)),
        fileSystem: fs,
      );

      engine.get('/template', (ctx) {
        return ctx.inertia(
          'Template',
          props: {'name': 'Ada'},
          templateContent: 'Component: {{ component }} {{ props.name }}',
        );
      });

      await engine.initialize();

      final response = await client.get('/template');
      expect(response.statusCode, equals(200), reason: response.body);
      response
          .assertHeaderContains('content-type', 'text/html')
          .assertBodyContains('Component: Template Ada');
    });

    engineTest('template is ignored for inertia requests', (
      engine,
      client,
    ) async {
      engine.get('/template', (ctx) {
        return ctx.inertia(
          'Template',
          props: {'name': 'Ada'},
          templateContent: 'Component: {{ component }} {{ props.name }}',
        );
      });

      final response = await client.get(
        '/template',
        headers: {
          'X-Inertia': ['true'],
        },
      );

      response
          .assertStatus(200)
          .assertHeaderContains('content-type', 'application/json')
          .assertJsonPath('component', 'Template');
    });

    engineTest('defaults to html builder', (engine, client) async {
      engine.get('/default', (ctx) {
        return ctx.inertia('Default', props: const {'name': 'Ada'});
      });

      final response = await client.get('/default');
      response
          .assertStatus(200)
          .assertHeaderContains('content-type', 'text/html')
          .assertBodyContains('data-page=');
    });

    engineTest('default html includes request url', (engine, client) async {
      engine.get('/users/', (ctx) {
        return ctx.inertia('Users', props: const {});
      });

      final response = await client.get('/users/?page=2&filter=a');

      response
          .assertStatus(200)
          .assertHeaderContains('content-type', 'text/html')
          .assertBodyContains(
            '&quot;url&quot;:&quot;/users/?page=2&amp;filter=a&quot;',
          );
    });

    engineTest('SSR head and body render once', (engine, client) async {
      final gateway = _CountingGateway();
      engine.get('/ssr-head', (ctx) {
        return ctx.inertia(
          'Ssr',
          props: const {'name': 'Ada'},
          ssrEnabled: true,
          ssrGateway: gateway,
        );
      });

      final response = await client.get('/ssr-head');

      response
          .assertStatus(200)
          .assertHeaderContains('content-type', 'text/html')
          .assertBodyContains('<title>SSR</title>')
          .assertBodyContains('<div>SSR body</div>');
      expect(gateway.calls, equals(1));
    });

    engineTest('SSR errors trigger callback', (engine, client) async {
      var called = false;
      engine.get('/ssr-error', (ctx) {
        return ctx.inertia(
          'Ssr',
          props: const {'name': 'Ada'},
          ssrEnabled: true,
          ssrGateway: _ThrowingGateway(),
          onSsrError: (error, stack) {
            called = true;
          },
          htmlBuilder: (page, ssr) => '<html>Fallback</html>',
        );
      });

      final response = await client.get('/ssr-error');
      response.assertStatus(200).assertBodyContains('Fallback');
      expect(called, isTrue);
    });
  });
}

class _ThrowingGateway implements SsrGateway {
  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<SsrResponse> render(String pageJson) async {
    throw StateError('SSR failed');
  }
}

class _CountingGateway implements SsrGateway {
  int calls = 0;

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<SsrResponse> render(String pageJson) async {
    calls += 1;
    return const SsrResponse(
      body: '<div>SSR body</div>',
      head: '<title>SSR</title>',
    );
  }
}
