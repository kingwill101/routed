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
