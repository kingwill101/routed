import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:routed_views/src/middleware/localization.dart';
import 'package:routed_views/src/translation/constants.dart';
import 'package:routed_views/src/translation/locale_manager.dart';
import 'package:routed_views/src/translation/resolvers.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

void main() {
  group('localizationMiddleware', () {
    test('stores resolved locale from query first', () async {
      final manager = LocaleManager(
        defaultLocale: 'en',
        fallbackLocale: 'en',
        resolvers: [
          QueryLocaleResolver(parameter: 'lang'),
          HeaderLocaleResolver(),
        ],
      );

      final engine = testEngine()
        ..addGlobalMiddleware(localizationMiddleware(manager))
        ..get('/welcome', (ctx) {
          return ctx.json({'locale': ctx.get<String>(kRequestLocaleAttribute)});
        });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get(
        '/welcome?lang=es',
        headers: {
          HttpHeaders.acceptLanguageHeader: ['fr-CA'],
        },
      );

      response.assertStatus(HttpStatus.ok);
      final body = (response.json() as Map).cast<String, dynamic>();
      expect(body['locale'], equals('es'));
    });

    test('falls back to header resolver when query missing', () async {
      final manager = LocaleManager(
        defaultLocale: 'en',
        fallbackLocale: 'en',
        resolvers: [HeaderLocaleResolver()],
      );

      final engine = testEngine()
        ..addGlobalMiddleware(localizationMiddleware(manager))
        ..get('/', (ctx) {
          return ctx.json({'locale': ctx.get<String>(kRequestLocaleAttribute)});
        });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get(
        '/',
        headers: {
          HttpHeaders.acceptLanguageHeader: ['de-DE,de;q=0.7'],
        },
      );

      final body = (response.json() as Map).cast<String, dynamic>();
      expect(body['locale'], equals('de-DE'));
    });
  });
}
