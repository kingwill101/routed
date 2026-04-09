import 'package:routed/src/contracts/translation/loader.dart';
import 'package:routed/src/translation/translator.dart';
import 'package:test/test.dart';

void main() {
  group('Translator', () {
    late StubTranslationLoader loader;

    setUp(() {
      loader = StubTranslationLoader();
    });

    test('translates keys with replacements', () {
      loader.seed('*', 'messages', 'en', {'welcome': 'Hello :name'});
      final translator = Translator(loader: loader, locale: 'en');

      final result = translator.translate(
        'messages.welcome',
        replacements: {'name': 'Ana'},
      );

      expect(result, equals('Hello Ana'));
    });

    test('falls back to configured locale when key is missing', () {
      loader.seed('*', 'messages', 'en', {'welcome': 'Welcome'});
      final translator = Translator(
        loader: loader,
        locale: 'fr',
        fallbackLocale: 'en',
      );

      expect(translator.translate('messages.welcome'), equals('Welcome'));
    });

    test('returns JSON translations when dot key is missing', () {
      loader.seed('*', '*', 'en', {'Submit': 'Enviar'});
      final translator = Translator(loader: loader, locale: 'en');

      expect(translator.translate('Submit'), equals('Enviar'));
    });

    test('choice selects pluralized branches and injects count', () {
      loader.seed('*', 'alerts', 'en', {
        'count': '{0} No alerts|{1} One alert|[2,*] :count alerts',
      });
      final translator = Translator(loader: loader, locale: 'en');

      expect(translator.choice('alerts.count', 0), equals('No alerts'));
      expect(translator.choice('alerts.count', 1), equals('One alert'));
      expect(translator.choice('alerts.count', 4), equals('4 alerts'));
    });

    test('addLines merges ad-hoc entries', () {
      final translator = Translator(loader: loader, locale: 'en');

      translator.addLines({'messages.goodbye': 'Bye'}, 'en');

      expect(translator.translate('messages.goodbye'), equals('Bye'));
    });

    test('missing key handler can override output', () {
      final translator = Translator(loader: loader, locale: 'en');
      translator.handleMissingKeysUsing((key, locale) => 'missing:$key');

      expect(
        translator.translate('messages.unknown'),
        equals('missing:messages.unknown'),
      );
    });

    group('choice() null-spread replacements fix', () {
      test('choice with null replacements still injects count', () {
        // Regression: before the ...?replacements fix, passing null replacements
        // to choice() would cause a runtime error or silently drop the count
        // injection.
        loader.seed('*', 'items', 'en', {
          'count': '{0} no items|{1} one item|[2,*] :count items',
        });
        final translator = Translator(loader: loader, locale: 'en');

        // null replacements – count must still be substituted.
        expect(translator.choice('items.count', 0), equals('no items'));
        expect(translator.choice('items.count', 1), equals('one item'));
        expect(
          translator.choice('items.count', 5, replacements: null),
          equals('5 items'),
        );
      });

      test('choice with non-null replacements merges count and user values',
          () {
        loader.seed('*', 'cart', 'en', {
          'summary': '{1} :count item in :store|[2,*] :count items in :store',
        });
        final translator = Translator(loader: loader, locale: 'en');

        final result = translator.choice(
          'cart.summary',
          3,
          replacements: {'store': 'MyShop'},
        );

        expect(result, equals('3 items in MyShop'));
      });

      test('choice does not override user-provided count in replacements', () {
        loader.seed('*', 'badge', 'en', {
          'label': '{1} :count badge|[2,*] :count badges',
        });
        final translator = Translator(loader: loader, locale: 'en');

        // The user explicitly passes count=99 so the template should use 99.
        final result = translator.choice(
          'badge.label',
          2,
          replacements: {'count': 99},
        );

        expect(result, equals('99 badges'));
      });

      test('choice with empty replacements map injects count', () {
        loader.seed('*', 'pages', 'en', {
          'total': '[0,*] :count pages',
        });
        final translator = Translator(loader: loader, locale: 'en');

        final result = translator.choice(
          'pages.total',
          7,
          replacements: <String, dynamic>{},
        );

        expect(result, equals('7 pages'));
      });

      test(
          'choice with null replacements at count=0 selects correct plural branch',
          () {
        loader.seed('*', 'alerts', 'en', {
          'msg': '{0} No alerts|[1,*] :count alert(s)',
        });
        final translator = Translator(loader: loader, locale: 'en');

        expect(
          translator.choice('alerts.msg', 0),
          equals('No alerts'),
        );
      });
    });
  });
}

class StubTranslationLoader implements TranslationLoader {
  final Map<String, Map<String, Map<String, Map<String, dynamic>>>> _store = {};
  final List<String> _paths = [];
  final List<String> _jsonPaths = [];
  final Map<String, String> _namespaces = {};

  void seed(
    String namespace,
    String group,
    String locale,
    Map<String, dynamic> lines,
  ) {
    final ns = namespace.isEmpty ? '*' : namespace;
    _store
        .putIfAbsent(ns, () => {})
        .putIfAbsent(group, () => {})
        .putIfAbsent(locale, () => {})
        .addAll(lines);
  }

  @override
  Map<String, dynamic> load(String locale, String group, {String? namespace}) {
    final ns = namespace == null || namespace.isEmpty ? '*' : namespace;
    final lines = _store[ns]?[group]?[locale];
    if (lines == null) {
      return <String, dynamic>{};
    }
    return Map<String, dynamic>.from(lines);
  }

  @override
  void addNamespace(String namespace, String hint) {
    _namespaces[namespace] = hint;
  }

  @override
  void setNamespaces(Map<String, String> namespaces) {
    _namespaces
      ..clear()
      ..addAll(namespaces);
  }

  @override
  Map<String, String> get namespaces => Map.unmodifiable(_namespaces);

  @override
  void setPaths(Iterable<String> paths) {
    _paths
      ..clear()
      ..addAll(paths);
  }

  @override
  void addPath(String path) {
    _paths.add(path);
  }

  @override
  List<String> get paths => List.unmodifiable(_paths);

  @override
  void setJsonPaths(Iterable<String> paths) {
    _jsonPaths
      ..clear()
      ..addAll(paths);
  }

  @override
  void addJsonPath(String path) {
    _jsonPaths.add(path);
  }

  @override
  List<String> get jsonPaths => List.unmodifiable(_jsonPaths);
}