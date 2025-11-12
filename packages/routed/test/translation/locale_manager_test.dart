import 'package:routed/src/translation/locale_manager.dart';
import 'package:routed/src/translation/locale_resolution.dart';
import 'package:routed/src/translation/resolvers.dart';
import 'package:test/test.dart';

LocaleResolutionContext contextFactory({
  Map<String, String>? headers,
  Map<String, String>? query,
  Map<String, String>? cookies,
  Map<String, String>? session,
}) {
  final headerMap = <String, String>{
    for (final entry in (headers ?? const <String, String>{}).entries)
      entry.key.toLowerCase(): entry.value,
  };
  final queryMap = query ?? const <String, String>{};
  final cookieMap = cookies ?? const <String, String>{};
  final sessionMap = session ?? const <String, String>{};
  return LocaleResolutionContext(
    header: (name) => headerMap[name.toLowerCase()],
    query: (name) => queryMap[name],
    cookie: (name) => cookieMap[name],
    sessionValue: session == null ? null : (name) => sessionMap[name],
  );
}

void main() {
  group('LocaleManager', () {
    test('honours resolver order and sanitizes locales', () {
      final manager = LocaleManager(
        defaultLocale: 'en',
        fallbackLocale: 'en',
        resolvers: [
          QueryLocaleResolver(parameter: 'lang'),
          HeaderLocaleResolver(),
        ],
      );

      final resolved = manager.resolve(
        contextFactory(
          query: {'lang': 'es_MX'},
          headers: {'Accept-Language': 'pt-BR,pt;q=0.8'},
        ),
      );

      expect(resolved, equals('es-MX'));
    });

    test('header resolver parses q-values', () {
      final manager = LocaleManager(
        defaultLocale: 'en',
        fallbackLocale: 'en',
        resolvers: [HeaderLocaleResolver()],
      );

      final resolved = manager.resolve(
        contextFactory(
          headers: {'Accept-Language': 'de-CH;q=0.8, fr-CH, en;q=0.4'},
        ),
      );

      expect(resolved, equals('fr-CH'));
    });

    test('session resolver returns null when session missing', () {
      final manager = LocaleManager(
        defaultLocale: 'en',
        fallbackLocale: 'en',
        resolvers: [SessionLocaleResolver(sessionKey: 'locale')],
      );

      final resolved = manager.resolve(contextFactory());
      expect(resolved, equals('en'));
    });
  });
}
