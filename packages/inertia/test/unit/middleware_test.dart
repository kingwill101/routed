/// Tests for middleware behavior.
library;

import 'package:test/test.dart';
import 'package:inertia_dart/inertia_dart.dart';

/// Runs middleware unit tests.
void main() {
  group('Middleware', () {
    test('VersionMiddleware returns location on mismatch', () async {
      final middleware = VersionMiddleware(versionResolver: () => '2');
      final request = InertiaRequest(
        headers: {'X-Inertia': 'true', 'X-Inertia-Version': '1'},
        url: '/home',
        method: 'GET',
      );

      final response = await middleware.handle(request, (req) async {
        return InertiaResponse.json(
          PageData(component: 'Home', props: const {}, url: '/home'),
        );
      });

      expect(response.statusCode, equals(409));
      expect(response.headers[InertiaHeaders.inertiaLocation], equals('/home'));
    });

    test('RedirectMiddleware rewrites non-post redirects', () async {
      final middleware = RedirectMiddleware();
      final request = InertiaRequest(
        headers: {'X-Inertia': 'true'},
        url: '/update',
        method: 'PUT',
      );

      final response = await middleware.handle(request, (req) async {
        return InertiaResponse(
          page: PageData(component: 'Home', props: const {}, url: '/update'),
          statusCode: 302,
        );
      });

      expect(response.statusCode, equals(303));
    });

    test('SharedDataMiddleware merges props', () async {
      final middleware = SharedDataMiddleware(
        sharedData: (request) => {'app': 'Routed'},
      );
      final request = InertiaRequest(
        headers: {'X-Inertia': 'true'},
        url: '/shared',
        method: 'GET',
      );

      final response = await middleware.handle(request, (req) async {
        return InertiaResponse.json(
          PageData(component: 'Shared', props: {'user': 'Ada'}, url: '/shared'),
        );
      });

      expect(response.page.props['app'], equals('Routed'));
      expect(response.page.props['user'], equals('Ada'));
    });

    test('EncryptHistoryMiddleware enables history encryption', () async {
      final middleware = EncryptHistoryMiddleware();
      final request = InertiaRequest(
        headers: {'X-Inertia': 'true'},
        url: '/secure',
        method: 'GET',
      );

      final response = await middleware.handle(request, (req) async {
        return InertiaResponse.json(
          PageData(component: 'Secure', props: const {}, url: '/secure'),
        );
      });

      expect(response.page.encryptHistory, isTrue);
    });

    test('EncryptHistoryMiddleware preserves existing flag', () async {
      final middleware = EncryptHistoryMiddleware();
      final request = InertiaRequest(
        headers: {'X-Inertia': 'true'},
        url: '/secure',
        method: 'GET',
      );

      final response = await middleware.handle(request, (req) async {
        return InertiaResponse.json(
          PageData(
            component: 'Secure',
            props: const {},
            url: '/secure',
            encryptHistory: true,
          ),
        );
      });

      expect(response.page.encryptHistory, isTrue);
    });

    test('ErrorHandlingMiddleware uses onError handler', () async {
      final middleware = ErrorHandlingMiddleware(
        onError: (error, stack) {
          return InertiaResponse.location('/error');
        },
      );
      final request = InertiaRequest(
        headers: {'X-Inertia': 'true'},
        url: '/fail',
        method: 'GET',
      );

      final response = await middleware.handle(request, (req) async {
        throw StateError('fail');
      });

      expect(response.statusCode, equals(409));
      expect(
        response.headers[InertiaHeaders.inertiaLocation],
        equals('/error'),
      );
    });
  });
}
