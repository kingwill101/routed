import 'dart:developer' as developer;

import 'package:routed/src/config/config.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/utils/deep_copy.dart';

typedef ConfigRegistryListener = void Function(ConfigRegistryEntry entry);

class ConfigRegistryEntry {
  ConfigRegistryEntry({
    required this.source,
    required Map<String, dynamic> defaults,
    Iterable<ConfigDocEntry> docs = const [],
  }) : defaults = deepCopyMap(defaults),
       docs = List<ConfigDocEntry>.unmodifiable(
         List<ConfigDocEntry>.from(docs),
       ),
       registeredAt = DateTime.now();

  final String source;
  final Map<String, dynamic> defaults;
  final List<ConfigDocEntry> docs;
  final DateTime registeredAt;
}

class ConfigRegistry {
  final List<ConfigRegistryEntry> _entries = [];
  final ConfigImpl _combined = ConfigImpl();
  final List<ConfigRegistryListener> _listeners = [];
  final List<ConfigDocEntry> _docs = [];

  void register(
    Map<String, dynamic> defaults, {
    String? source,
    Iterable<ConfigDocEntry> docs = const [],
  }) {
    if (defaults.isEmpty) return;
    final entry = ConfigRegistryEntry(
      source: source ?? 'unknown',
      defaults: defaults,
      docs: docs,
    );
    _entries.add(entry);
    _combined.merge(entry.defaults);
    if (entry.docs.isNotEmpty) {
      _validateDocEntries(entry, source: entry.source);
      _docs.addAll(entry.docs);
    }
    for (final listener in _listeners) {
      listener(entry);
    }
  }

  Map<String, dynamic> combinedDefaults() {
    return deepCopyMap(_combined.all());
  }

  List<ConfigRegistryEntry> get entries => List.unmodifiable(_entries);

  List<ConfigDocEntry> get docs => List.unmodifiable(_docs);

  void addListener(ConfigRegistryListener listener) {
    _listeners.add(listener);
  }

  void removeListener(ConfigRegistryListener listener) {
    _listeners.remove(listener);
  }

  void _validateDocEntries(
    ConfigRegistryEntry entry, {
    required String source,
  }) {
    for (final doc in entry.docs) {
      if (!_shouldValidatePath(doc.path)) continue;
      if (_docPathExists(entry.defaults, doc.path)) continue;
      developer.log(
        'Config documentation path "${doc.path}" declared by $source does '
        'not match a key in its defaultConfig map. Double-check for typos or '
        'update defaultConfigDocs to use wildcards (e.g. "*").',
        name: 'ConfigRegistry',
        level: 900, // warning
      );
    }
  }

  bool _shouldValidatePath(String path) {
    return !path.contains('*') && !path.contains('[');
  }

  bool _docPathExists(Map<String, dynamic> defaults, String path) {
    final segments = path
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .toList();
    dynamic current = defaults;
    for (final segment in segments) {
      if (current is Map<String, dynamic>) {
        if (!current.containsKey(segment)) {
          return false;
        }
        current = current[segment];
        continue;
      }
      if (current is Map) {
        if (!current.containsKey(segment)) {
          return false;
        }
        current = current[segment];
        continue;
      }
      return false;
    }
    return true;
  }
}
