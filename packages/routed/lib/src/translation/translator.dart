import 'package:routed/src/contracts/translation/loader.dart';
import 'package:routed/src/contracts/translation/translator.dart';
import 'package:routed/src/translation/message_selector.dart';
import 'package:routed/src/utils/dot.dart';

class Translator implements TranslatorContract {
  Translator({
    required TranslationLoader loader,
    required String locale,
    String? fallbackLocale,
    MessageSelector? selector,
  }) : _loader = loader,
       _locale = locale,
       _fallbackLocale = fallbackLocale,
       _selector = selector ?? MessageSelector();

  final TranslationLoader _loader;
  final MessageSelector _selector;
  final Map<String, Map<String, Map<String, Map<String, dynamic>>>> _loaded =
      {};
  String _locale;
  String? _fallbackLocale;
  Object? Function(String key, String locale)? _missingKeyHandler;
  bool _handleMissingKeys = true;

  @override
  String get locale => _locale;

  @override
  set locale(String value) => _locale = value;

  @override
  String? get fallbackLocale => _fallbackLocale;

  @override
  set fallbackLocale(String? value) => _fallbackLocale = value;

  @override
  bool has(String key, {String? locale, bool fallback = true}) {
    final resolved = translate(key, locale: locale, fallback: fallback);
    return !(resolved is String && resolved == key);
  }

  @override
  bool hasForLocale(String key, String locale) {
    return has(key, locale: locale, fallback: false);
  }

  @override
  Object? translate(
    String key, {
    Map<String, dynamic>? replacements,
    String? locale,
    bool fallback = true,
  }) {
    final resolvedLocale = locale ?? _locale;
    final normalizedKey = key.trim();

    final jsonLine = _loadJsonLine(normalizedKey, resolvedLocale);
    if (jsonLine != null) {
      if (jsonLine is String) {
        return _applyReplacements(jsonLine, replacements);
      }
      if (jsonLine is Map<String, dynamic>) {
        return _replaceDeep(jsonLine, replacements);
      }
      return jsonLine;
    }

    final parsed = _ParsedKey.parse(normalizedKey);
    final locales = _localeCandidates(resolvedLocale, fallback);
    for (final candidate in locales) {
      final line = _getLine(
        parsed.namespace,
        parsed.group,
        candidate,
        parsed.item,
        replacements,
      );
      if (line != null) {
        return line;
      }
    }

    final handled = _handleMissingKey(normalizedKey, resolvedLocale);
    if (handled != null) {
      if (handled is String) {
        return _applyReplacements(handled, replacements);
      }
      return handled;
    }

    return _applyReplacements(normalizedKey, replacements);
  }

  @override
  String choice(
    String key,
    num count, {
    Map<String, dynamic>? replacements,
    String? locale,
  }) {
    final targetLocale = _localeForChoice(key, locale ?? _locale);
    final raw =
        translate(
          key,
          locale: targetLocale,
          replacements: replacements,
          fallback: false,
        )?.toString() ??
        key;
    final selected = _selector.choose(raw, count, targetLocale);
    final resolved = <String, dynamic>{
      if (replacements != null) ...replacements,
      if (!(replacements?.containsKey('count') ?? false)) 'count': count,
    };
    return _applyReplacements(selected, resolved);
  }

  @override
  void addLines(
    Map<String, dynamic> lines,
    String locale, {
    String namespace = '*',
  }) {
    final sanitizedNamespace = namespace.isEmpty ? '*' : namespace;
    final namespaceBucket = _loaded.putIfAbsent(
      sanitizedNamespace,
      () => <String, Map<String, Map<String, dynamic>>>{},
    );
    lines.forEach((key, value) {
      final segments = key.split('.');
      if (segments.length < 2) {
        return;
      }
      final group = segments.first;
      final item = segments.skip(1).join('.');
      final groupBucket = namespaceBucket.putIfAbsent(
        group,
        () => <String, Map<String, dynamic>>{},
      );
      final localeBucket = groupBucket.putIfAbsent(
        locale,
        () => <String, dynamic>{},
      );
      dot(localeBucket).set(item, value);
    });
  }

  @override
  void handleMissingKeysUsing(
    Object? Function(String key, String locale)? callback,
  ) {
    _missingKeyHandler = callback;
  }

  List<String> _localeCandidates(String locale, bool fallback) {
    if (!fallback || _fallbackLocale == null || _fallbackLocale == locale) {
      return [locale];
    }
    if (_fallbackLocale == null) {
      return [locale];
    }
    if (locale == _fallbackLocale) {
      return [locale];
    }
    return [locale, _fallbackLocale!];
  }

  String _localeForChoice(String key, String locale) {
    if (hasForLocale(key, locale)) {
      return locale;
    }
    return _fallbackLocale ?? locale;
  }

  Object? _loadJsonLine(String key, String locale) {
    final jsonBucket = _loadGroup('*', '*', locale, namespaceAware: false);
    if (jsonBucket == null) {
      return null;
    }
    return jsonBucket[key];
  }

  Object? _getLine(
    String namespace,
    String group,
    String locale,
    String item,
    Map<String, dynamic>? replacements,
  ) {
    final bucket = _loadGroup(namespace, group, locale);
    if (bucket == null) {
      return null;
    }
    if (item.isEmpty) {
      return _replaceDeep(bucket, replacements);
    }
    final segments = item.split('.');
    Object? current = bucket;
    for (final segment in segments) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    if (current is String) {
      return _applyReplacements(current, replacements);
    }
    if (current is Map<String, dynamic>) {
      return _replaceDeep(current, replacements);
    }
    if (current is Map) {
      return _replaceDeep(
        current.map((key, value) => MapEntry(key.toString(), value)),
        replacements,
      );
    }
    return current;
  }

  Map<String, dynamic>? _loadGroup(
    String namespace,
    String group,
    String locale, {
    bool namespaceAware = true,
  }) {
    final normalizedNamespace = namespace.isEmpty ? '*' : namespace;
    final namespaceBucket = _loaded.putIfAbsent(
      normalizedNamespace,
      () => <String, Map<String, Map<String, dynamic>>>{},
    );
    final groupBucket = namespaceBucket.putIfAbsent(
      group,
      () => <String, Map<String, dynamic>>{},
    );
    if (!groupBucket.containsKey(locale)) {
      final lines = _loader.load(
        locale,
        group,
        namespace: namespaceAware ? namespace : '*',
      );
      groupBucket[locale] = Map<String, dynamic>.from(lines);
    }
    return groupBucket[locale];
  }

  Object? _handleMissingKey(String key, String locale) {
    if (!_handleMissingKeys || _missingKeyHandler == null) {
      return null;
    }
    _handleMissingKeys = false;
    try {
      return _missingKeyHandler?.call(key, locale);
    } finally {
      _handleMissingKeys = true;
    }
  }

  String _applyReplacements(String line, Map<String, dynamic>? replacements) {
    if (replacements == null || replacements.isEmpty) {
      return line;
    }
    var output = line;
    replacements.forEach((key, value) {
      final stringValue = value?.toString() ?? '';
      output = output.replaceAll(':$key', stringValue);
      output = output.replaceAll(
        ':${_capitalize(key)}',
        _capitalize(stringValue),
      );
      output = output.replaceAll(
        ':${key.toUpperCase()}',
        stringValue.toUpperCase(),
      );
    });
    return output;
  }

  Map<String, dynamic> _replaceDeep(
    Map<String, dynamic> input,
    Map<String, dynamic>? replacements,
  ) {
    final result = <String, dynamic>{};
    input.forEach((key, value) {
      result[key] = _replaceValue(value, replacements);
    });
    return result;
  }

  dynamic _replaceValue(dynamic value, Map<String, dynamic>? replacements) {
    if (value is String) {
      return _applyReplacements(value, replacements);
    }
    if (value is Map<String, dynamic>) {
      return _replaceDeep(value, replacements);
    }
    if (value is Map) {
      return _replaceDeep(
        value.map((key, inner) => MapEntry(key.toString(), inner)),
        replacements,
      );
    }
    if (value is Iterable) {
      return value.map((item) => _replaceValue(item, replacements)).toList();
    }
    return value;
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    if (value.length == 1) {
      return value.toUpperCase();
    }
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _ParsedKey {
  _ParsedKey({
    required this.namespace,
    required this.group,
    required this.item,
  });

  final String namespace;
  final String group;
  final String item;

  factory _ParsedKey.parse(String key) {
    var namespace = '*';
    var remainder = key;
    final namespaceSplit = key.split('::');
    if (namespaceSplit.length == 2) {
      namespace = namespaceSplit.first.isEmpty ? '*' : namespaceSplit.first;
      remainder = namespaceSplit.last;
    }
    final dotIndex = remainder.indexOf('.');
    if (dotIndex == -1) {
      return _ParsedKey(namespace: namespace, group: remainder, item: '');
    }
    final group = remainder.substring(0, dotIndex);
    final item = remainder.substring(dotIndex + 1);
    return _ParsedKey(namespace: namespace, group: group, item: item);
  }
}
