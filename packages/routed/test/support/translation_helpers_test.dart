import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed/src/translation/constants.dart';
import 'package:server_testing/mock.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

class StubTranslator implements TranslatorContract {
  StubTranslator(this.locale, this.fallbackLocale);

  @override
  String locale;

  @override
  String? fallbackLocale;

  @override
  bool has(String key, {String? locale, bool fallback = true}) => true;

  @override
  bool hasForLocale(String key, String locale) => true;

  @override
  Object? translate(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  }) {
    return 'value-${locale ?? this.locale}';
  }

  @override
  String choice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  }) {
    return 'choice-${locale ?? this.locale}-$count';
  }

  @override
  void addLines(
    Map<String, dynamic> lines,
    String locale, {
    String namespace = '*',
  }) {}

  @override
  void handleMissingKeysUsing(
    Object? Function(String key, String locale)? callback,
  ) {}
}

EngineContext _context(Container container) {
  final mockRequest = setupRequest('GET', '/');
  final mockResponse = setupResponse();
  when(mockResponse.flush()).thenAnswer((_) async {});
  when(mockResponse.close()).thenAnswer((_) async {});
  when(mockResponse.done).thenAnswer((_) => Future.value());

  final request = Request(mockRequest, const {}, EngineConfig());
  final response = Response(mockResponse);
  return EngineContext(
    request: request,
    response: response,
    container: container,
  );
}

void main() {
  group('translation helpers', () {
    test('trans uses request locale override', () async {
      final engine = testEngine(includeDefaultProviders: false);
      engine.container
        ..instance<Config>(
          ConfigImpl({
            'app': {'locale': 'en'},
          }),
        )
        ..instance<TranslatorContract>(StubTranslator('en', 'en'));

      final ctx = _context(engine.container)
        ..set(kRequestLocaleAttribute, 'es');

      await AppZone.run(
        engine: engine,
        context: ctx,
        body: () async {
          expect(trans('messages.greeting'), equals('value-es'));
          expect(transChoice('messages.count', 2), equals('choice-es-2'));
        },
      );
    });

    test('currentLocale falls back to translator locale', () async {
      final engine = testEngine(includeDefaultProviders: false);
      engine.container
        ..instance<Config>(
          ConfigImpl({
            'app': {'locale': 'en'},
          }),
        )
        ..instance<TranslatorContract>(StubTranslator('fr', 'en'));

      final ctx = _context(engine.container);

      await AppZone.run(
        engine: engine,
        context: ctx,
        body: () async {
          expect(currentLocale(), equals('fr'));
        },
      );
    });
  });
}
