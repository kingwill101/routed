import 'dart:async';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/src/middleware/localization.dart';
import 'package:routed/src/translation/constants.dart';
import 'package:routed/src/translation/locale_manager.dart';
import 'package:routed/src/translation/resolvers.dart';
import 'package:server_testing/mock.dart';
import 'package:test/test.dart';

EngineContext _buildContext(
  String uri, {
  Map<String, List<String>>? headers,
  List<Cookie>? cookies,
}) {
  final mockRequest = setupRequest(
    'GET',
    uri,
    requestHeaders: headers,
    cookies: cookies,
  );
  final mockResponse = setupResponse();
  when(mockResponse.flush()).thenAnswer((_) async {});
  when(mockResponse.close()).thenAnswer((_) async {});
  when(mockResponse.done).thenAnswer((_) => Future.value());

  final request = Request(mockRequest, const {}, EngineConfig());
  final response = Response(mockResponse);
  final container = Container()..instance<Config>(ConfigImpl());

  return EngineContext(
    request: request,
    response: response,
    container: container,
  );
}

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

      final ctx = _buildContext(
        '/welcome?lang=es',
        headers: {
          HttpHeaders.acceptLanguageHeader: ['fr-CA'],
        },
      );

      final response = await localizationMiddleware(manager)(
        ctx,
        () async => ctx.response,
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(ctx.get<String>(kRequestLocaleAttribute), equals('es'));
    });

    test('falls back to header resolver when query missing', () async {
      final manager = LocaleManager(
        defaultLocale: 'en',
        fallbackLocale: 'en',
        resolvers: [HeaderLocaleResolver()],
      );

      final ctx = _buildContext(
        '/',
        headers: {
          HttpHeaders.acceptLanguageHeader: ['de-DE,de;q=0.7'],
        },
      );

      await localizationMiddleware(manager)(ctx, () async => ctx.response);

      expect(ctx.get<String>(kRequestLocaleAttribute), equals('de-DE'));
    });
  });
}
