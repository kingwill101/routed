import 'package:meta/meta.dart';

/// A shared base class for simple string-keyed registries.
///
/// Subclasses use the protected methods to manage, retrieve, and list
/// entries while maintaining control over their public APIs.
abstract class NamedRegistry<V> {
  /// Creates an instance of [NamedRegistry].
  NamedRegistry();

  /// Internal map to store registry entries.
  final Map<String, V> _entries = <String, V>{};

  /// Internal map to track the origin of each entry.
  final Map<String, StackTrace> _origins = <String, StackTrace>{};

  /// Registers an entry with the given [name] and [value].
  ///
  /// If [overrideExisting] is `true`, an existing entry with the same name
  /// will be replaced. Returns `true` if the entry was successfully registered.
  ///
  /// Throws an [ArgumentError] if the [name] is empty.
  @protected
  bool registerEntry(String name, V value, {bool overrideExisting = true}) {
    final key = normalizeName(name);
    if (key.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Registry key cannot be empty.');
    }

    final existing = _entries[key];
    if (existing != null) {
      final shouldOverride = onDuplicate(key, existing, overrideExisting);
      if (!shouldOverride) {
        return false;
      }
    }

    _entries[key] = value;
    _origins[key] = StackTrace.current;
    return true;
  }

  /// Unregisters the entry with the given [name].
  ///
  /// Returns `true` if the entry was successfully removed.
  @protected
  bool unregisterEntry(String name) {
    final key = normalizeName(name);
    final removed = _entries.remove(key);
    _origins.remove(key);
    return removed != null;
  }

  /// Clears all entries from the registry.
  @protected
  void clearEntries() {
    _entries.clear();
    _origins.clear();
  }

  /// Retrieves the entry associated with the given [name].
  ///
  /// Returns `null` if no entry exists for the given name.
  @protected
  V? getEntry(String name) => _entries[normalizeName(name)];

  /// Checks if an entry with the given [name] exists in the registry.
  @protected
  bool containsEntry(String name) => _entries.containsKey(normalizeName(name));

  /// An iterable of all entry names in the registry.
  Iterable<String> get entryNames => _entries.keys;

  /// Provides direct access to the internal map of entries.
  @protected
  Map<String, V> get entries => _entries;

  /// Normalizes the given [name] by trimming and converting it to lowercase.
  @protected
  String normalizeName(String name) => name.trim().toLowerCase();

  /// Retrieves the stack trace of the original registration for the given [name].
  ///
  /// Returns `null` if no origin is available for the given name.
  @protected
  StackTrace? entryOrigin(String name) => _origins[normalizeName(name)];

  /// Generates diagnostic information for duplicate entries with the given [name].
  ///
  /// Includes the stack trace of the original registration, if available.
  @protected
  String duplicateDiagnostics(String name) {
    final origin = entryOrigin(name);
    if (origin == null) {
      return '';
    }
    return '\nOriginal registration stack trace:\n$origin';
  }

  /// Handles duplicate entries with the given [name] and [existing] value.
  ///
  /// Returns `true` if the existing entry should be overridden.
  @protected
  bool onDuplicate(String name, V existing, bool overrideExisting) =>
      overrideExisting;
}
