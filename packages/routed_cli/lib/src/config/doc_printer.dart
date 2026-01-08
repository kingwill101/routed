import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:routed/providers.dart' show ProviderRegistry;
import 'package:routed/routed.dart';

Map<String, List<ConfigDocEntry>> collectConfigDocs() {
  final mergedByPath = <String, ConfigDocEntry>{};
  for (final registration in ProviderRegistry.instance.registrations) {
    final provider = registration.factory();
    if (provider is ProvidesDefaultConfig) {
      final defaults = provider.defaultConfig;
      final allDocs = List<ConfigDocEntry>.from(defaults.docs);

      if (provider.schemas.isNotEmpty) {
        for (final entry in provider.schemas.entries) {
          allDocs.addAll(
              ConfigSchema.toDocEntries(entry.value, pathBase: entry.key));
        }
      }

      for (final entry in allDocs) {
        final root = _rootFromPath(entry.path);
        if (root == null) continue;
        final existing = mergedByPath[entry.path];
        if (existing == null) {
          mergedByPath[entry.path] = entry;
        } else {
          mergedByPath[entry.path] = _mergeDocEntries(existing, entry);
        }
      }
    }
  }
  final docsByRoot = <String, List<ConfigDocEntry>>{};
  for (final entry in mergedByPath.values) {
    final root = _rootFromPath(entry.path);
    if (root == null) continue;
    docsByRoot.putIfAbsent(root, () => <ConfigDocEntry>[]).add(entry);
  }
  return docsByRoot;
}

String prependConfigDocComments(
  String relativePath,
  String content,
  Map<String, List<ConfigDocEntry>> docsByRoot,
) {
  final root = _rootForTemplate(relativePath);
  if (root == null) return content;
  final entries = docsByRoot[root];
  if (entries == null || entries.isEmpty) return content;

  final buffer = StringBuffer();
  buffer.writeln('# ${_titleCase(root)} configuration quick reference:');

  final sorted = List<ConfigDocEntry>.from(entries)
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final entry in sorted) {
    final localPath = entry.path.startsWith('$root.')
        ? entry.path.substring(root.length + 1)
        : entry.path;
    final segments = <String>[];
    if (entry.description != null && entry.description!.isNotEmpty) {
      segments.add(entry.description!);
    }
    final defaultValue = entry.defaultValue;
    final defaultNote = entry.metadata['default_note'];
    if (defaultValue != null) {
      segments.add('Default: ${_formatDefault(defaultValue)}.');
    } else if (defaultNote is String && defaultNote.isNotEmpty) {
      segments.add('Default: ${_ensureTrailingPeriod(defaultNote.trim())}');
    }
    if (entry.metadata['required'] == true) {
      segments.add('Required.');
    }
    final validation = entry.metadata['validation'];
    if (validation is String && validation.trim().isNotEmpty) {
      segments.add('Validation: ${_ensureTrailingPeriod(validation.trim())}');
    }
    final inheritFromEnv = entry.metadata[configDocMetaInheritFromEnv];
    if (inheritFromEnv is String && inheritFromEnv.isNotEmpty) {
      segments.add('Env override: $inheritFromEnv');
    }
    final options = entry.resolveOptions();
    if (options != null && options.isNotEmpty) {
      segments.add('Options: ${options.join(", ")}');
    }
    if (entry.type != null && entry.type!.isNotEmpty) {
      segments.add('Type: ${entry.type}');
    }
    if (segments.isEmpty) {
      continue;
    }
    buffer.writeln('# $localPath – ${segments.join(' ')}');
  }

  buffer.writeln();
  buffer.write(content);
  return buffer.toString();
}

String renderConfigDocsJson(Map<String, List<ConfigDocEntry>> docsByRoot) {
  final orderedKeys = docsByRoot.keys.toList()..sort();
  final payload = <String, Object?>{};
  for (final key in orderedKeys) {
    final entries = List<ConfigDocEntry>.from(docsByRoot[key]!)
      ..sort((a, b) => a.path.compareTo(b.path));
    final list = <Map<String, Object?>>[];
    for (final entry in entries) {
      final map = <String, Object?>{
        'path': entry.path,
        if (entry.type != null) 'type': entry.type,
        if (entry.description != null) 'description': entry.description,
        if (entry.example != null) 'example': entry.example,
        if (entry.deprecated) 'deprecated': entry.deprecated,
      };
      final options = entry.resolveOptions();
      if (options != null) {
        map['options'] = options;
      }
      if (entry.metadata.isNotEmpty) {
        map['metadata'] = entry.metadata;
      }
      list.add(map);
    }
    payload[key] = list;
  }
  return const JsonEncoder.withIndent('  ').convert(payload);
}

String? _rootForTemplate(String relativePath) {
  if (!relativePath.startsWith('config/')) return null;
  final basename = p.basenameWithoutExtension(relativePath);
  return basename.isEmpty ? null : basename;
}

String? _rootFromPath(String path) {
  final index = path.indexOf('.');
  if (index == -1) return path.isEmpty ? null : path;
  return index == 0 ? null : path.substring(0, index);
}

String _titleCase(String input) {
  if (input.isEmpty) return input;
  if (input.length == 1) return input.toUpperCase();
  return '${input[0].toUpperCase()}${input.substring(1)}';
}

String _formatDefault(Object value) {
  if (value is String) {
    if (value.isEmpty) {
      return '(empty)';
    }
    if (value.contains(' ')) {
      return '"$value"';
    }
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  if (value is Iterable || value is Map) {
    return jsonEncode(value);
  }
  return value.toString();
}

String _ensureTrailingPeriod(String value) {
  if (value.isEmpty) {
    return value;
  }
  final trimmed = value.trimRight();
  return trimmed.endsWith('.') ? trimmed : '$trimmed.';
}

ConfigDocEntry _mergeDocEntries(
  ConfigDocEntry existing,
  ConfigDocEntry incoming,
) {
  String? betterDescription(String? a, String? b) {
    if ((a ?? '').trim().isEmpty && (b ?? '').trim().isEmpty) {
      return null;
    }
    if ((a ?? '').trim().isEmpty) return b;
    if ((b ?? '').trim().isEmpty) return a;
    return a!.length >= b!.length ? a : b;
  }

  String? betterString(String? a, String? b) {
    if (a == null || a.isEmpty) return b;
    return a;
  }

  Object? betterDefault(Object? a, Object? b) => a ?? b;

  final mergedMetadata = <String, Object?>{
    ...existing.metadata,
    ...incoming.metadata,
  };

  return ConfigDocEntry(
    path: existing.path,
    type: betterString(existing.type, incoming.type),
    description: betterDescription(existing.description, incoming.description),
    example: betterString(existing.example, incoming.example),
    deprecated: existing.deprecated || incoming.deprecated,
    options: existing.options ?? incoming.options,
    optionsBuilder: existing.optionsBuilder ?? incoming.optionsBuilder,
    metadata: mergedMetadata,
    defaultValue: betterDefault(existing.defaultValue, incoming.defaultValue),
  );
}
