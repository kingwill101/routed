import 'package:routed/routed.dart';
import 'package:routed/src/translation/constants.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
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

void main() {
  group('translation helpers', () {
    test('trans uses request locale override', () async {
      final engine = testEngine();
      engine.container
        ..instance<Config>(
          ConfigImpl({
            'app': {'locale': 'en'},
          }),
        )
        ..instance<TranslatorContract>(StubTranslator('en', 'en'));

      engine.get('/trans', (ctx) async {
        ctx.set(kRequestLocaleAttribute, 'es');
        return ctx.json({
          'greeting': ctx.trans('messages.greeting'),
          'choice': ctx.transChoice('messages.count', 2),
        });
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get('/trans');
      expect(response.json()['greeting'], equals('value-es'));
      expect(response.json()['choice'], equals('choice-es-2'));
    });

    test('currentLocale falls back to translator locale', () async {
      final engine = testEngine();
      engine.container
        ..instance<Config>(
          ConfigImpl({
            'app': {'locale': 'en'},
          }),
        )
        ..instance<TranslatorContract>(StubTranslator('fr', 'en'));

      engine.get('/locale', (ctx) async {
        return ctx.json({'locale': ctx.currentLocale()});
      });

      await engine.initialize();
      final client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
      addTearDown(() async {
        await client.close();
        await engine.close();
      });

      final response = await client.get('/locale');
      expect(response.json()['locale'], equals('fr'));
    });
  });
}
