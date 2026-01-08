import 'dart:developer' as developer;

import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/config.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/utils/deep_copy.dart';
import 'package:routed/src/utils/deep_merge.dart';

typedef ConfigRegistryListener = void Function(ConfigRegistryEntry entry);

class ConfigRegistryEntry {
  ConfigRegistryEntry({
    required this.source,
    required Map<String, dynamic> defaults,
    Iterable<ConfigDocEntry> docs = const [],
    Map<String, Schema> schemas = const {},
  }) : defaults = deepCopyMap(defaults),
       docs = List<ConfigDocEntry>.unmodifiable(
         List<ConfigDocEntry>.from(docs),
       ),
       schemas = Map<String, Schema>.unmodifiable(schemas),
       registeredAt = DateTime.now();

  final String source;
  final Map<String, dynamic> defaults;
  final List<ConfigDocEntry> docs;
  final Map<String, Schema> schemas;
  final DateTime registeredAt;
}

class ConfigRegistry {
  final List<ConfigRegistryEntry> _entries = [];
  final ConfigImpl _combined = ConfigImpl();
  final List<ConfigRegistryListener> _listeners = [];
  final List<ConfigDocEntry> _docs = [];
  final Map<String, Map<String, dynamic>> _rawSchemas = {};

  void register(
    Map<String, dynamic> defaults, {
    String? source,
    Iterable<ConfigDocEntry> docs = const [],
    Map<String, Schema> schemas = const {},
  }) {
    if (defaults.isEmpty && schemas.isEmpty) return;
    final entry = ConfigRegistryEntry(
      source: source ?? 'unknown',
      defaults: defaults,
      docs: docs,
      schemas: schemas,
    );
    _entries.add(entry);
    _combined.merge(entry.defaults);
    if (entry.docs.isNotEmpty) {
      _validateDocEntries(entry, source: entry.source);
      _docs.addAll(entry.docs);
    }

    if (entry.schemas.isNotEmpty) {
      for (final sEntry in entry.schemas.entries) {
        final existing = _rawSchemas[sEntry.key];
        if (existing == null) {
          _rawSchemas[sEntry.key] = deepCopyMap(sEntry.value.value);
        } else {
          deepMerge(existing, sEntry.value.value, override: true);
        }
      }
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

  Map<String, Schema> get schemas =>
      _rawSchemas.map((key, value) => MapEntry(key, Schema.fromMap(value)));

  /// Generates a complete JSON Schema for the registered configuration.
  Map<String, dynamic> generateJsonSchema({
    String title = 'Routed Configuration',
    String? id,
  }) {
    final properties = <String, Map<String, Object?>>{};

    for (final entry in _rawSchemas.entries) {
      properties[entry.key] = Map<String, Object?>.from(entry.value);
    }

    return {
      if (id != null) '\$id': id,
      '\$schema': 'http://json-schema.org/draft-07/schema#',
      'title': title,
      'type': 'object',
      'properties': properties,
    };
  }

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
      // Skip validation if the doc entry doesn't provide a default value.
      // It's valid to document a key that doesn't have a default.
      if (!doc.hasExplicitDefault) continue;

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
