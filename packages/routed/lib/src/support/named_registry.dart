import 'package:meta/meta.dart';

/// Shared base for simple string-keyed registries.
///
/// Subclasses call the protected helpers to store, resolve, and enumerate
/// entries while keeping control of their public APIs.
abstract class NamedRegistry<V> {
  NamedRegistry();

  final Map<String, V> _entries = <String, V>{};

  @protected
  bool registerEntry(String name, V value, {bool overrideExisting = true}) {
    final key = normalizeName(name);
    if (key.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Registry key cannot be empty');
    }

    final existing = _entries[key];
    if (existing != null) {
      final shouldOverride = onDuplicate(key, existing, overrideExisting);
      if (!shouldOverride) {
        return false;
      }
    }

    _entries[key] = value;
    return true;
  }

  @protected
  bool unregisterEntry(String name) {
    return _entries.remove(normalizeName(name)) != null;
  }

  @protected
  V? getEntry(String name) => _entries[normalizeName(name)];

  @protected
  bool containsEntry(String name) => _entries.containsKey(normalizeName(name));

  Iterable<String> get entryNames => _entries.keys;

  @protected
  Map<String, V> get entries => _entries;

  @protected
  String normalizeName(String name) => name;

  @protected
  bool onDuplicate(String name, V existing, bool overrideExisting) =>
      overrideExisting;
}
