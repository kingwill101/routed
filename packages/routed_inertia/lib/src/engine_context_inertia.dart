import 'dart:convert' as convert;

import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';

import 'config/inertia_config.dart';

/// Inertia helper methods on [EngineContext].
extension EngineContextInertia on EngineContext {
  static const String _sharedKey = 'inertia.shared';
  static const String _encryptHistoryKey = 'inertia.encryptHistory';
  static const String _clearHistoryKey = 'inertia.clearHistory';
  static const String _flashKey = 'inertia.flash';
  static const String _errorsKey = 'inertia.errors';

  /// Add shared Inertia props for the current request.
  void inertiaShare(Map<String, dynamic> props) {
    final shared = _sharedProps();
    shared.addAll(props);
  }

  /// Render an Inertia response using the current request context.
  Future<Response> inertia(
    String component, {
    Map<String, dynamic> props = const {},
    String? url,
    String version = '',
    bool? encryptHistory,
    bool? clearHistory,
    List<int>? cache,
    String? templateName,
    String? templateContent,
    Map<String, dynamic> templateData = const {},
    SsrGateway? ssrGateway,
    bool ssrEnabled = false,
    void Function(Object error, StackTrace stack)? onSsrError,
    String Function(PageData page, SsrResponse? ssr)? htmlBuilder,
  }) async {
    final headers = _extractHeaders(this.headers);
    final isInertia = InertiaHeaderUtils.isInertiaRequest(headers);
    final requestedProps =
        InertiaHeaderUtils.getPartialData(headers) ?? const [];
    final requestedExceptProps =
        InertiaHeaderUtils.getPartialExcept(headers) ?? const [];
    final config = _resolveInertiaConfig();

    final sharedProps = _sharedProps().all();
    final errors = _consumeErrors(InertiaHeaderUtils.getErrorBag(headers));
    final mergedProps = <String, dynamic>{
      ...sharedProps,
      if (errors != null) 'errors': AlwaysProp(() => errors),
      ...props,
    };

    final context = PropertyContext(
      headers: headers,
      isPartialReload:
          requestedProps.isNotEmpty || requestedExceptProps.isNotEmpty,
      requestedProps: requestedProps,
      requestedExceptProps: requestedExceptProps,
    );

    final encryptHistoryValue =
        encryptHistory ??
        getContextData<bool>(_encryptHistoryKey) ??
        config?.history.encrypt ??
        false;
    final clearHistoryValue = clearHistory ?? _consumeClearHistoryFlag();
    final flash = _consumeFlash();
    final resolvedVersion = version.isEmpty
        ? (config?.resolveVersion() ?? '')
        : version;

    final page = await InertiaResponseFactory().buildPageDataAsync(
      component: component,
      props: mergedProps,
      url: url ?? _requestUrl(requestedUri, headers: this.headers),
      context: context,
      version: resolvedVersion,
      encryptHistory: encryptHistoryValue,
      clearHistory: clearHistoryValue,
      flash: flash,
      cache: cache,
    );

    if (isInertia) {
      setHeader(InertiaHeaders.inertia, 'true');
      setHeader(InertiaHeaders.inertiaVary, InertiaHeaders.inertia);
      return json(page.toJson());
    }

    final resolvedTemplateName = templateName ?? config?.rootView;
    final resolvedGateway = ssrGateway ?? config?.ssrGateway;
    final resolvedSsrEnabled = ssrEnabled || (config?.ssr.enabled ?? false);

    SsrResponse? ssrResponse;
    if (resolvedSsrEnabled && resolvedGateway != null) {
      try {
        final pageJson = convert.jsonEncode(page.toJson());
        ssrResponse = await resolvedGateway.render(pageJson);
      } catch (error, stack) {
        if (onSsrError != null) {
          onSsrError(error, stack);
        }
      }
    }

    if (resolvedTemplateName != null || templateContent != null) {
      final pageJson = convert.jsonEncode(page.toJson());
      final data = <String, dynamic>{
        'page': page.toJson(),
        'pageJson': pageJson,
        'pageJsonEscaped': _escapeHtml(pageJson),
        'props': page.props,
        'component': page.component,
        'url': page.url,
        'version': page.version,
        if (ssrResponse != null)
          'ssr': {'body': ssrResponse.body, 'head': ssrResponse.head},
        if (ssrResponse != null) 'ssrBody': ssrResponse.body,
        if (ssrResponse != null) 'ssrHead': ssrResponse.head,
        ...templateData,
      };

      return template(
        content: templateContent,
        templateName: resolvedTemplateName,
        data: data,
      );
    }

    final htmlContent =
        htmlBuilder?.call(page, ssrResponse) ?? _defaultHtml(page, ssrResponse);
    return html(htmlContent);
  }

  InertiaSharedProps _sharedProps() {
    final existing = getContextData<InertiaSharedProps>(_sharedKey);
    if (existing != null) return existing;
    final created = InertiaSharedProps();
    setContextData(_sharedKey, created);
    return created;
  }

  /// Enable or disable history encryption for this request.
  void inertiaEncryptHistory([bool value = true]) {
    setContextData(_encryptHistoryKey, value);
  }

  /// Clear Inertia history for the next response.
  void inertiaClearHistory() {
    try {
      setSession(_clearHistoryKey, true);
    } catch (_) {
      setContextData(_clearHistoryKey, true);
    }
  }

  /// Flash Inertia data for the next response.
  void inertiaFlash(Object keyOrMap, [dynamic value]) {
    final data = <String, dynamic>{};
    if (keyOrMap is Map<String, dynamic>) {
      data.addAll(keyOrMap);
    } else if (keyOrMap is String) {
      data[keyOrMap] = value;
    } else {
      throw ArgumentError(
        'inertiaFlash expects a String or Map<String, dynamic>.',
      );
    }

    try {
      final existing = getSession<Map<String, dynamic>>(_flashKey) ?? {};
      setSession(_flashKey, {...existing, ...data});
    } catch (_) {
      final existing = getContextData<Map<String, dynamic>>(_flashKey) ?? {};
      setContextData(_flashKey, {...existing, ...data});
    }
  }

  /// Store validation errors for the next Inertia response.
  void inertiaErrors(Map<String, dynamic> errors, {String bag = 'default'}) {
    try {
      final existing = getSession<Map<String, dynamic>>(_errorsKey) ?? {};
      setSession(_errorsKey, {...existing, bag: errors});
    } catch (_) {
      final existing = getContextData<Map<String, dynamic>>(_errorsKey) ?? {};
      setContextData(_errorsKey, {...existing, bag: errors});
    }
  }

  bool _consumeClearHistoryFlag() {
    try {
      final value = getSession<bool>(_clearHistoryKey) ?? false;
      if (value) {
        removeSession(_clearHistoryKey);
      }
      return value;
    } catch (_) {
      final value = getContextData<bool>(_clearHistoryKey) ?? false;
      if (value) {
        setContextData(_clearHistoryKey, null);
      }
      return value;
    }
  }

  Map<String, dynamic>? _consumeFlash() {
    try {
      final data = getSession<Map<String, dynamic>>(_flashKey);
      if (data != null) {
        removeSession(_flashKey);
      }
      return data;
    } catch (_) {
      final data = getContextData<Map<String, dynamic>>(_flashKey);
      if (data != null) {
        setContextData(_flashKey, null);
      }
      return data;
    }
  }

  Map<String, dynamic>? _consumeErrors(String? errorBag) {
    Map<String, dynamic>? errors;
    try {
      errors = getSession<Map<String, dynamic>>(_errorsKey);
      if (errors != null) {
        removeSession(_errorsKey);
      }
    } catch (_) {
      errors = getContextData<Map<String, dynamic>>(_errorsKey);
      if (errors != null) {
        setContextData(_errorsKey, null);
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

  InertiaConfig? _resolveInertiaConfig() {
    if (!container.has<InertiaConfig>()) {
      return null;
    }
    try {
      return container.get<InertiaConfig>();
    } catch (_) {
      return null;
    }
  }
}

Map<String, String> _extractHeaders(HttpHeaders headers) {
  final result = <String, String>{};
  headers.forEach((name, values) {
    if (values.isNotEmpty) {
      result[name] = values.first;
    }
  });
  return result;
}

String _defaultHtml(PageData page, SsrResponse? ssrResponse) {
  final pageJson = convert.jsonEncode(page.toJson());
  final escaped = _escapeHtml(pageJson);
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

String _requestUrl(Uri uri, {HttpHeaders? headers}) {
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

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}
