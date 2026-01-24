import 'package:routed/routed.dart';
import 'package:routed_inertia/routed_inertia.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  group('RoutedInertiaMiddleware', () {
    engineTest(
      'returns location on version mismatch',
      (engine, client) async {
        engine.get('/version', (ctx) => ctx.json({'ok': true}));

        final response = await client.get(
          '/version',
          headers: {
            'X-Inertia': ['true'],
            'X-Inertia-Version': ['old'],
          },
        );

        response
            .assertStatus(409)
            .assertHeaderContains('X-Inertia-Location', '/version');
      },
      options: [
        withMiddleware([RoutedInertiaMiddleware(versionResolver: () => 'new')]),
      ],
    );

    engineTest(
      'rewrites redirect status for non-post',
      (engine, client) async {
        engine.put('/redirect', (ctx) async => ctx.redirect('/target'));

        final response = await client.put(
          '/redirect',
          '',
          headers: {
            'X-Inertia': ['true'],
            'X-Inertia-Version': ['1'],
          },
        );

        response.assertStatus(303);
      },
      options: [
        withMiddleware([RoutedInertiaMiddleware(versionResolver: () => '1')]),
      ],
    );

    engineTest(
      'ignores non-inertia requests',
      (engine, client) async {
        engine.put('/redirect', (ctx) async => ctx.redirect('/target'));

        final response = await client.put('/redirect', '');

        response.assertStatus(302);
      },
      options: [
        withMiddleware([RoutedInertiaMiddleware(versionResolver: () => '1')]),
      ],
    );
  });
}
