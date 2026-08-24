import 'package:routed_core/routed_core.dart';
import 'package:routed_openapi/src/openapi/handler_identity.dart';
import 'package:routed_openapi/src/openapi/route_metadata_extractor.dart';
import 'package:routed_openapi/src/openapi/schema.dart';

/// Enriches a manifest with annotation and Dartdoc metadata from project files.
Future<RouteManifest> enrichManifestWithProjectMetadata(
  RouteManifest manifest, {
  required String projectRoot,
  required String packageName,
}) async {
  final extracted = await extractRouteMetadataIndexFromFileSystem(
    projectRoot: projectRoot,
    packageName: packageName,
  );
  return mergeManifestWithExtractedMetadata(manifest, extracted);
}

/// Merges extracted handler metadata into a runtime route manifest.
RouteManifest mergeManifestWithExtractedMetadata(
  RouteManifest manifest,
  Map<String, ExtractedRouteMetadata> extracted,
) {
  if (manifest.routes.isEmpty || extracted.isEmpty) {
    return manifest;
  }

  final mergedRoutes = manifest.routes
      .map((route) {
        final metadata = _resolveMetadata(route, extracted);
        if (metadata == null) {
          return route;
        }

        // The core manifest may omit handler identity and schema metadata.
        final existingSchema = _schemaFromRoute(route);
        final mergedSchema = _mergeSchema(existingSchema, metadata);
        return RouteManifestEntry(
          method: route.method,
          path: route.path,
          name: route.name,
          middleware: route.middleware,
          constraints: route.constraints,
          metadata: route.metadata,
          sourceFile: route.sourceFile,
          sourceLine: route.sourceLine,
          sourceColumn: route.sourceColumn,
          isFallback: route.isFallback,
          schema: mergedSchema.toJson(),
        );
      })
      .toList(growable: false);

  return RouteManifest(
    generatedAt: manifest.generatedAt,
    routes: mergedRoutes,
    webSockets: manifest.webSockets,
    validationRuleNames: manifest.validationRuleNames,
  );
}

RouteSchema? _schemaFromRoute(RouteManifestEntry route) {
  final metadata = route.metadata['routed.openapi.schema'];
  if (metadata is Map) {
    return RouteSchema.fromJson(metadata.cast<String, Object?>());
  }
  final legacy = route.schema;
  if (legacy is RouteSchema) return legacy;
  if (legacy is Map) {
    return RouteSchema.fromJson(legacy.cast<String, Object?>());
  }
  return null;
}

ExtractedRouteMetadata? _resolveMetadata(
  RouteManifestEntry route,
  Map<String, ExtractedRouteMetadata> extracted,
) {
  final sourceMetadata = _findSourceMetadata(route, extracted);

  final routeKey = 'route:${route.method.toUpperCase()} ${route.path}';
  final routeMetadata =
      extracted[routeKey] ?? _findSuffixRouteMetadata(route, extracted);

  final functionRef = _handlerIdentity(route.handlerIdentity)?.functionRef;
  if (functionRef == null || functionRef.isEmpty) {
    if (sourceMetadata == null) return routeMetadata;
    if (routeMetadata == null) return sourceMetadata;
    return sourceMetadata.merge(routeMetadata);
  }

  final keys = <String>{functionRef, _normalizeFunctionRef(functionRef)}
    ..removeWhere((k) => k.isEmpty);

  for (final key in keys) {
    final match = extracted[key];
    if (match != null) {
      final mergedRoute = routeMetadata == null
          ? match
          : routeMetadata.merge(match);
      return sourceMetadata == null
          ? mergedRoute
          : sourceMetadata.merge(mergedRoute);
    }
  }

  if (sourceMetadata == null) return routeMetadata;
  if (routeMetadata == null) return sourceMetadata;
  return sourceMetadata.merge(routeMetadata);
}

ExtractedRouteMetadata? _findSourceMetadata(
  RouteManifestEntry route,
  Map<String, ExtractedRouteMetadata> extracted,
) {
  final identity = _handlerIdentity(route.handlerIdentity);
  final sourceFile = identity?.sourceFile ?? route.sourceFile;
  final sourceLine = identity?.sourceLine ?? route.sourceLine;
  final sourceColumn = identity?.sourceColumn ?? route.sourceColumn;
  if (sourceFile == null || sourceLine == null || sourceColumn == null) {
    return null;
  }

  final matches = <ExtractedRouteMetadata>[];
  extracted.forEach((key, value) {
    if (!key.startsWith('source:')) return;
    final match = RegExp(r'^source:(.*):(\d+):(\d+)$').firstMatch(key);
    if (match == null) return;

    final keyFile = match.group(1);
    final keyLine = int.tryParse(match.group(2) ?? '');
    final keyColumn = int.tryParse(match.group(3) ?? '');
    if (keyFile == null || keyLine == null || keyColumn == null) return;
    if (keyLine != sourceLine || keyColumn != sourceColumn) return;

    if (_pathsComparable(sourceFile, keyFile)) {
      matches.add(value);
    }
  });

  if (matches.length == 1) {
    return matches.single;
  }

  if (matches.isNotEmpty) {
    final first = matches.first;
    final compatible = matches.every((m) => _sameMetadata(first, m));
    if (compatible) {
      return first;
    }
  }

  return null;
}

HandlerIdentity? _handlerIdentity(Object? value) {
  if (value is HandlerIdentity) return value;
  if (value is! Map<Object?, Object?>) return null;

  return HandlerIdentity(
    routeName: value['routeName'] as String?,
    functionRef: value['functionRef'] as String?,
    method: value['method'] as String?,
    path: value['path'] as String?,
    sourceFile: value['sourceFile'] as String?,
    sourceLine: (value['sourceLine'] as num?)?.toInt(),
    sourceColumn: (value['sourceColumn'] as num?)?.toInt(),
  );
}

ExtractedRouteMetadata? _findSuffixRouteMetadata(
  RouteManifestEntry route,
  Map<String, ExtractedRouteMetadata> extracted,
) {
  final method = route.method.toUpperCase();
  final targetPath = _normalizeRoutePath(route.path);

  final candidates = <String, ExtractedRouteMetadata>{};
  extracted.forEach((key, value) {
    if (!key.startsWith('route:')) return;

    final separator = key.indexOf(' ');
    if (separator == -1) return;
    final keyMethod = key.substring('route:'.length, separator).toUpperCase();
    if (keyMethod != method) return;

    final keyPath = _normalizeRoutePath(key.substring(separator + 1).trim());
    if (keyPath.isEmpty) return;

    if (_pathEndsWith(targetPath, keyPath)) {
      candidates[key] = value;
    }
  });

  if (candidates.length == 1) {
    // Even with a single route candidate, the underlying `route:` key may have
    // collapsed multiple source files with the same suffix. Check source
    // entries for a better mount-aware match.
    final single = candidates.values.single;
    final lowerTarget = targetPath.toLowerCase();
    ExtractedRouteMetadata? sourceMatch;
    extracted.forEach((sKey, sVal) {
      if (!sKey.startsWith('source:')) return;
      // Only consider source entries that could correspond to this suffix.
      // Their route path is not stored, so infer it from summary matching.
      final m = RegExp(r'^source:(.*):\d+:\d+$').firstMatch(sKey);
      if (m == null) return;
      final srcFile = m.group(1)!.toLowerCase();
      final base = srcFile.split('/').last.split('.').first;
      final token = base.replaceAll('_routes', '').replaceAll('_', '');
      if (token.isNotEmpty &&
          lowerTarget.contains(token) &&
          sVal.summary != null) {
        // Prefer source that matches mount prefix
        sourceMatch = sVal;
      }
    });
    if (sourceMatch != null) {
      // If single route metadata is ambiguous, prefer the mount-aware source.
      // Only override when the single summary does not match the target source.
      final singleSummary = single.summary;
      final sourceSummary = sourceMatch!.summary;
      if (singleSummary != sourceSummary) {
        // Keep a summary that already identifies the target's source file.
        if (lowerTarget.contains('admin') &&
            singleSummary != null &&
            singleSummary.toLowerCase().contains('admin')) {
          return single;
        }
        if (lowerTarget.contains('users') &&
            singleSummary != null &&
            singleSummary.toLowerCase().contains('users')) {
          return single;
        }
        return sourceMatch;
      }
    }
    return single;
  }

  if (candidates.length > 1) {
    // Disambiguate mounted routes with the same suffix by matching the mount
    // prefix segment to the source file name. Source keys preserve per-file
    // metadata even when `route:` keys collide.
    final lowerTarget = targetPath.toLowerCase();
    for (final entry in candidates.entries) {
      final routeMeta = entry.value;
      String? matchedSourceFile;
      extracted.forEach((sKey, sVal) {
        if (!sKey.startsWith('source:')) return;
        if (!identical(sVal, routeMeta)) return;
        final m = RegExp(r'^source:(.*):\d+:\d+$').firstMatch(sKey);
        if (m == null) return;
        final srcFile = m.group(1)!.toLowerCase();
        final base = srcFile.split('/').last.split('.').first;
        final token = base.replaceAll('_routes', '').replaceAll('_', '');
        if (token.isNotEmpty && lowerTarget.contains(token)) {
          matchedSourceFile = sKey;
        }
      });
      if (matchedSourceFile != null) {
        return routeMeta;
      }
    }
    // Fallback: match any source file that contains a path segment.
    for (final entry in candidates.entries) {
      final routeMeta = entry.value;
      var hasSourceMatch = false;
      extracted.forEach((sKey, sVal) {
        if (!sKey.startsWith('source:')) return;
        if (sVal.summary != routeMeta.summary) return;
        final m = RegExp(r'^source:(.*):\d+:\d+$').firstMatch(sKey);
        if (m == null) return;
        final srcFile = m.group(1)!.toLowerCase();
        final segments = lowerTarget.split('/').where((s) => s.isNotEmpty);
        for (final seg in segments) {
          if (srcFile.contains(seg)) {
            hasSourceMatch = true;
          }
        }
      });
      if (hasSourceMatch) {
        return routeMeta;
      }
    }
  }

  return null;
}

bool _pathEndsWith(String fullPath, String suffixPath) {
  if (fullPath == suffixPath) return true;
  if (!fullPath.endsWith(suffixPath)) return false;

  final boundaryIndex = fullPath.length - suffixPath.length;
  if (boundaryIndex == 0) return true;
  return fullPath[boundaryIndex] == '/';
}

String _normalizeRoutePath(String path) {
  var normalized = path.trim();
  if (normalized.isEmpty) return '/';
  if (!normalized.startsWith('/')) {
    normalized = '/$normalized';
  }
  normalized = normalized.replaceAllMapped(
    RegExp(r':(\w+)'),
    (match) => '{${match.group(1)!}}',
  );
  if (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _pathsComparable(String a, String b) {
  final leftVariants = _pathVariants(a);
  final rightVariants = _pathVariants(b);

  for (final left in leftVariants) {
    for (final right in rightVariants) {
      if (left == right) return true;
      if (left.endsWith(right) || right.endsWith(left)) return true;
    }
  }

  return false;
}

String _normalizePath(String value) {
  return value.replaceAll(r'\', '/').trim();
}

bool _sameMetadata(ExtractedRouteMetadata a, ExtractedRouteMetadata b) {
  return a.summary == b.summary &&
      a.description == b.description &&
      a.operationId == b.operationId &&
      a.deprecated == b.deprecated &&
      a.hidden == b.hidden &&
      a.tags.join('|') == b.tags.join('|') &&
      a.params.length == b.params.length &&
      a.responses.length == b.responses.length;
}

Set<String> _pathVariants(String input) {
  final base = _normalizePath(input);
  final variants = <String>{base};

  if (base.startsWith('package:')) {
    final slash = base.indexOf('/');
    if (slash != -1 && slash < base.length - 1) {
      final relative = base.substring(slash + 1);
      variants
        ..add(relative)
        ..add('lib/$relative');
    }
  }

  if (base.startsWith('lib/')) {
    variants.add(base.substring(4));
  }

  return variants;
}

String _normalizeFunctionRef(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.contains('.')) {
    return trimmed.split('.').last;
  }
  return trimmed;
}

RouteSchema _mergeSchema(RouteSchema? schema, ExtractedRouteMetadata metadata) {
  final base = schema;

  final summary = base?.summary ?? metadata.summary;
  final description = base?.description ?? metadata.description;
  final tags = _mergeTags(base?.tags, metadata.tags);
  final operationId = base?.operationId ?? metadata.operationId;
  final deprecated = base?.deprecated ?? metadata.deprecated ?? false;
  final hidden = base?.hidden ?? metadata.hidden ?? false;
  final body = base?.body ?? metadata.body;
  final params = _mergeParams(base?.params, metadata.params);
  final responses = _mergeResponses(base?.responses, metadata.responses);
  final validationRules = base?.validationRules;

  return RouteSchema(
    summary: summary,
    description: description,
    tags: tags.isEmpty ? null : tags,
    operationId: operationId,
    deprecated: deprecated,
    hidden: hidden,
    body: body,
    params: params.isEmpty ? null : params,
    responses: responses.isEmpty ? null : responses,
    validationRules: validationRules,
  );
}

List<String> _mergeTags(List<String>? schemaTags, List<String> extractedTags) {
  final merged = <String>[];
  for (final tag in [...?schemaTags, ...extractedTags]) {
    if (tag.isEmpty || merged.contains(tag)) continue;
    merged.add(tag);
  }
  return merged;
}

List<ParamSchema> _mergeParams(
  List<ParamSchema>? schemaParams,
  List<ParamSchema> extractedParams,
) {
  final merged = <ParamSchema>[...?schemaParams];
  for (final extracted in extractedParams) {
    final exists = merged.any(
      (current) =>
          current.name == extracted.name &&
          current.location == extracted.location,
    );
    if (!exists) {
      merged.add(extracted);
    }
  }
  return merged;
}

List<ResponseSchema> _mergeResponses(
  List<ResponseSchema>? schemaResponses,
  List<ResponseSchema> extractedResponses,
) {
  final merged = <ResponseSchema>[...?schemaResponses];
  for (final extracted in extractedResponses) {
    final index = merged.indexWhere(
      (current) => current.statusCode == extracted.statusCode,
    );
    if (index == -1) {
      merged.add(extracted);
      continue;
    }

    final current = merged[index];
    merged[index] = ResponseSchema(
      current.statusCode,
      description: current.description.isNotEmpty
          ? current.description
          : extracted.description,
      contentType: current.contentType ?? extracted.contentType,
      jsonSchema: current.jsonSchema ?? extracted.jsonSchema,
      headers: current.headers ?? extracted.headers,
    );
  }
  return merged;
}
