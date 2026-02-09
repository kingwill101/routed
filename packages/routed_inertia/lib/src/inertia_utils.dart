import 'dart:convert' as convert;

import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';

import 'config/inertia_config.dart';

/// Keys used for Inertia session / context-data storage.
class InertiaKeys {
  InertiaKeys._();

  static const String shared = 'inertia.shared';
  static const String encryptHistory = 'inertia.encryptHistory';
  static const String clearHistory = 'inertia.clearHistory';
  static const String flash = 'inertia.flash';
  static const String errors = 'inertia.errors';
}

/// Builds a request URL from a [Uri], respecting the `X-Forwarded-Prefix`
/// header when present.
String inertiaRequestUrl(Uri uri, {HttpHeaders? headers}) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  final prefix = headers?.value('x-forwarded-prefix');
  final resolvedPath = _applyForwardedPrefix(path, prefix);
  if (uri.hasQuery) {
    return '$resolvedPath?${uri.query}';
  }
  return resolvedPath;
}

String _applyForwardedPrefix(String path, String? prefix) {
  if (prefix == null) return path;
  var normalized = prefix.trim();
  if (normalized.isEmpty) return path;
  if (!normalized.startsWith('/')) {
    normalized = '/$normalized';
  }
  if (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized.isEmpty) return path;
  if (path == normalized || path.startsWith('$normalized/')) {
    return path;
  }
  if (path == '/') {
    return normalized;
  }
  return '$normalized$path';
}

/// Generates a minimal HTML page for an Inertia initial visit.
String inertiaDefaultHtml(PageData page, SsrResponse? ssrResponse) {
  final pageJson = convert.jsonEncode(page.toJson());
  final escaped = escapeInertiaHtml(pageJson);
  final head = ssrResponse?.head ?? '';
  final bodyContent = ssrResponse?.body ?? '';
  final app = bodyContent.isEmpty
      ? '<div id="app" data-page="$escaped"></div>'
      : '<div id="app" data-page="$escaped">$bodyContent</div>';
  return '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    $head
    <title>Inertia</title>
  </head>
  <body>
    $app
  </body>
</html>
''';
}

/// Consumes the clear-history flag from session or context data.
bool consumeClearHistoryFlag(EngineContext ctx) {
  try {
    final value = ctx.getSession<bool>(InertiaKeys.clearHistory) ?? false;
    if (value) {
      ctx.removeSession(InertiaKeys.clearHistory);
    }
    return value;
  } catch (_) {
    final value = ctx.getContextData<bool>(InertiaKeys.clearHistory) ?? false;
    if (value) {
      ctx.setContextData(InertiaKeys.clearHistory, null);
    }
    return value;
  }
}

/// Consumes flash data from session or context data.
Map<String, dynamic>? consumeFlash(EngineContext ctx) {
  try {
    final data = ctx.getSession<Map<String, dynamic>>(InertiaKeys.flash);
    if (data != null) {
      ctx.removeSession(InertiaKeys.flash);
    }
    return data;
  } catch (_) {
    final data = ctx.getContextData<Map<String, dynamic>>(InertiaKeys.flash);
    if (data != null) {
      ctx.setContextData(InertiaKeys.flash, null);
    }
    return data;
  }
}

/// Consumes validation errors from session or context data.
///
/// If an [errorBag] is specified and a `default` key exists in the stored
/// errors, the returned map is scoped to that bag.
Map<String, dynamic>? consumeErrors(EngineContext ctx, String? errorBag) {
  Map<String, dynamic>? errors;
  try {
    errors = ctx.getSession<Map<String, dynamic>>(InertiaKeys.errors);
    if (errors != null) {
      ctx.removeSession(InertiaKeys.errors);
    }
  } catch (_) {
    errors = ctx.getContextData<Map<String, dynamic>>(InertiaKeys.errors);
    if (errors != null) {
      ctx.setContextData(InertiaKeys.errors, null);
    }
  }

  if (errors == null || errors.isEmpty) return null;
  if (errors.containsKey('default')) {
    if (errorBag != null) {
      return {errorBag: errors['default']};
    }
    final defaultBag = errors['default'];
    if (defaultBag is Map<String, dynamic>) {
      return defaultBag;
    }
    return {'default': defaultBag};
  }
  return errors;
}

/// Resolves the [InertiaConfig] from the DI container, if registered.
InertiaConfig? resolveInertiaConfig(EngineContext ctx) {
  if (!ctx.container.has<InertiaConfig>()) {
    return null;
  }
  try {
    return ctx.container.get<InertiaConfig>();
  } catch (_) {
    return null;
  }
}

/// Resolves Vite asset tags using the given [InertiaConfig].
Future<InertiaViteAssetTags?> resolveInertiaAssets(
  InertiaConfig? config,
) async {
  if (config == null) return null;
  final assetsConfig = config.assets;
  final entry = assetsConfig.entry ?? 'index.html';
  final includeReactRefresh = _shouldIncludeReactRefresh(entry);
  final assets = InertiaViteAssets(
    entry: entry,
    manifestPath:
        assetsConfig.manifestPath ?? 'client/dist/.vite/manifest.json',
    hotFile: assetsConfig.hotFile ?? 'client/public/hot',
    baseUrl: assetsConfig.baseUrl,
    devServerUrl: assetsConfig.resolveDevServerUrl(),
    includeReactRefresh: includeReactRefresh,
  );
  try {
    return await assets.resolve();
  } catch (_) {
    return const InertiaViteAssetTags();
  }
}

bool _shouldIncludeReactRefresh(String entry) {
  final lower = entry.toLowerCase().trim();
  return lower.endsWith('.jsx') || lower.endsWith('.tsx');
}
