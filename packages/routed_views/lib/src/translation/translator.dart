// The dot-path helper is not exported by routed_core's public barrel, so this
// package uses its stable internal utility while keeping the rest of the
// translator dependencies on public APIs.
// ignore_for_file: implementation_imports
import 'package:routed_core/routed_core.dart'
    show TranslationLoader, TranslatorContract;
import 'package:routed_core/src/utils/dot.dart';
import 'package:routed_views/src/translation/message_selector.dart';

/// Resolves and formats translations supplied by a [TranslationLoader].
///
/// Keys conventionally use `group.item` for grouped files and
/// `namespace::group.item` for namespaced files. A key without a group can
/// address a flat JSON dictionary. Resolved strings support `:name`,
/// `:Name`, and `:NAME` replacements; non-string values and nested maps are
/// returned as structured data.
///
/// ```dart
/// final translator = Translator(
///   loader: loader,
///   locale: 'fr-CA',
///   fallbackLocale: 'en',
/// );
/// final greeting = translator.translate(
///   'messages.greeting',
///   replacements: {'name': 'Ada'},
/// );
/// ```
class Translator implements TranslatorContract {
  /// Creates a translator for [locale] and an optional [fallbackLocale].
  ///
  /// [loader] supplies uncached translation groups. [selector] controls the
  /// branch chosen by [choice]; when omitted, [MessageSelector] is used.
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

  /// The locale used when a lookup does not provide an explicit locale.
  ///
  /// Changing this value affects subsequent lookups; it does not clear lines
  /// already cached by the translator.
  @override
  String get locale => _locale;

  @override
  set locale(String value) => _locale = value;

  /// The locale tried after the requested locale does not contain a key.
  ///
  /// Set this property to `null` to disable the fallback lookup. Changing it
  /// affects subsequent lookups and does not clear the existing cache.
  @override
  String? get fallbackLocale => _fallbackLocale;

  @override
  set fallbackLocale(String? value) => _fallbackLocale = value;

  /// Reports whether [key] resolves in the selected locale or its fallback.
  ///
  /// An explicit [locale] overrides [locale] for this call. Set [fallback] to
  /// `false` to restrict the check to that locale. A non-null value returned by
  /// the missing-key handler also counts as a resolution.
  @override
  bool has(String key, {String? locale, bool fallback = true}) {
    final resolved = translate(key, locale: locale, fallback: fallback);
    return !(resolved is String && resolved == key);
  }

  /// Reports whether [key] resolves in [locale] without using a fallback.
  @override
  bool hasForLocale(String key, String locale) {
    return has(key, locale: locale, fallback: false);
  }

  /// Resolves [key] and applies optional [replacements].
  ///
  /// [locale] overrides the current [locale] for this call. When [fallback]
  /// is `true`, [fallbackLocale] is tried after the requested locale. The
  /// result may be a string, scalar, nested map, or list. If no translation
  /// exists, the missing-key handler is given a chance to supply a value;
  /// otherwise the trimmed key is returned.
  ///
  /// ```dart
  /// final value = translator.translate(
  ///   'messages.welcome',
  ///   replacements: {'name': 'Ada'},
  /// );
  /// ```
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

  /// Selects the pluralized branch for [key] and [count].
  ///
  /// The requested locale is used when it contains [key]. Otherwise the
  /// configured fallback locale is tried. The selected message receives a
  /// `count` replacement unless [replacements] already provides one.
  ///
  /// ```dart
  /// final label = translator.choice('messages.files', 3);
  /// ```
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
      ...?replacements,
      if (!(replacements?.containsKey('count') ?? false)) 'count': count,
    };
    return _applyReplacements(selected, resolved);
  }

  /// Adds or replaces in-memory lines for [locale] and [namespace].
  ///
  /// Each entry in [lines] should use `group.item` notation, for example
  /// `{'messages.greeting': 'Hello'}`. The default `*` namespace represents
  /// application translations. Entries without a dot are ignored because no
  /// group can be inferred from them.
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

  /// Installs or clears the callback used for missing translation keys.
  ///
  /// The callback receives the unresolved key and locale. Returning a non-null
  /// value makes that value the translation; returning `null` preserves the
  /// normal behavior of returning the key. Pass `null` to remove the handler.
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

  final String namespace;
  final String group;
  final String item;
}
