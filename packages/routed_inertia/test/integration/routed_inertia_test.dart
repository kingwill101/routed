import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:routed_inertia/routed_inertia.dart';
import 'package:test/test.dart';

void main() {
  group('Routed Inertia', () {
    engineTest('renders Inertia JSON response', (engine, client) async {
      final inertia = RoutedInertia();
      engine.get('/dashboard', (ctx) {
        return inertia.render(ctx, 'Dashboard', {
          'user': {'name': 'Ada'},
        });
      });

      final response = await client.get(
        '/dashboard',
        headers: {
          'X-Inertia': ['true'],
          'Accept': ['application/json'],
        },
      );

      response
          .assertStatus(200)
          .assertHeaderContains('X-Inertia', 'true')
          .assertHeaderContains('Vary', 'X-Inertia')
          .assertJsonPath('component', 'Dashboard')
          .assertJsonPath('props.user.name', 'Ada');
    });

    engineTest('renders HTML with SSR response', (engine, client) async {
      final inertia = RoutedInertia(
        ssrEnabled: true,
        ssrGateway: _FakeSsrGateway(),
        templateRenderer: (page, ssr) {
          return '<html><body>${ssr?.body}</body></html>';
        },
      );
      engine.get('/ssr', (ctx) {
        return inertia.render(ctx, 'Ssr', {'title': 'SSR'});
      });

      final response = await client.get('/ssr');
      response.assertStatus(200).assertBodyContains('SSR body');
    });
  });
}

class _FakeSsrGateway implements SsrGateway {
  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<SsrResponse> render(String pageJson) async {
    return const SsrResponse(
      body: '<div>SSR body</div>',
      head: '<title>SSR</title>',
    );
  }
}
