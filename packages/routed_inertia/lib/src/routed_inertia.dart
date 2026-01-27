import 'dart:convert';
import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';

import 'config/inertia_config.dart';

export 'middleware/routed_inertia_middleware.dart';
export 'middleware/inertia_encrypt_history_middleware.dart';
export 'package:inertia_dart/inertia_dart.dart'
    show
        EncryptHistoryMiddleware,
        ErrorHandlingMiddleware,
        InertiaMiddleware,
        RedirectMiddleware,
        SharedDataMiddleware,
        VersionMiddleware;
export 'engine_context_inertia.dart';
export 'config/inertia_config.dart';
export 'provider/inertia_provider.dart';

/// Routed integration for Inertia responses
class RoutedInertia {
  static const String _flashKey = 'inertia.flash';
  static const String _errorsKey = 'inertia.errors';

  RoutedInertia({
    InertiaResponseFactory? responseFactory,
    String Function(PageData page, SsrResponse? ssr)? templateRenderer,
    this.ssrGateway,
    this.ssrEnabled = false,
  }) : responseFactory = responseFactory ?? InertiaResponseFactory(),
       templateRenderer = templateRenderer ?? _defaultTemplateRenderer;
  final InertiaResponseFactory responseFactory;
  final String Function(PageData page, SsrResponse? ssr) templateRenderer;
  final SsrGateway? ssrGateway;
  final bool ssrEnabled;

  /// Render an Inertia response using the current EngineContext
  Future<Response> render(
    EngineContext ctx,
    String component,
    Map<String, dynamic> props, {
    String? url,
    String version = '',
    bool encryptHistory = false,
    bool clearHistory = false,
    List<int>? cache,
  }) async {
    final headers = _extractHeaders(ctx.headers);
    final isInertia = InertiaHeaderUtils.isInertiaRequest(headers);
    final requestedProps =
        InertiaHeaderUtils.getPartialData(headers) ?? const [];
    final requestedExceptProps =
        InertiaHeaderUtils.getPartialExcept(headers) ?? const [];
    final config = _resolveInertiaConfig(ctx);

    final errors = _consumeErrors(ctx, InertiaHeaderUtils.getErrorBag(headers));
    final mergedProps = <String, dynamic>{
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

    final flash = _consumeFlash(ctx);
    final resolvedVersion = version.isEmpty
        ? (config?.resolveVersion() ?? '')
        : version;
    final resolvedEncryptHistory =
        encryptHistory || (config?.history.encrypt ?? false);
    final resolvedGateway = ssrGateway ?? config?.ssrGateway;
    final resolvedSsrEnabled = ssrEnabled || (config?.ssr.enabled ?? false);

    final page = await responseFactory.buildPageDataAsync(
      component: component,
      props: mergedProps,
      url: url ?? _requestUrl(ctx.requestedUri, headers: ctx.headers),
      context: context,
      version: resolvedVersion,
      encryptHistory: resolvedEncryptHistory,
      clearHistory: clearHistory,
      flash: flash,
      cache: cache,
    );

    if (isInertia) {
      ctx.setHeader(InertiaHeaders.inertia, 'true');
      ctx.setHeader(InertiaHeaders.inertiaVary, InertiaHeaders.inertia);
      return ctx.json(page.toJson());
    }

    SsrResponse? ssrResponse;
    if (resolvedSsrEnabled && resolvedGateway != null) {
      try {
        final pageJson = jsonEncode(page.toJson());
        ssrResponse = await resolvedGateway.render(pageJson);
      } catch (_) {
        ssrResponse = null;
      }
    }

    final html = templateRenderer(page, ssrResponse);
    return ctx.html(html);
  }

  static Map<String, String> _extractHeaders(HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      if (values.isNotEmpty) {
        result[name] = values.first;
      }
    });
    return result;
  }

  static String _defaultTemplateRenderer(PageData page, SsrResponse? ssr) {
    final json = jsonEncode(page.toJson());
    final escaped = _escapeHtml(json);
    final body = ssr?.body ?? '';
    if (body.isEmpty) {
      return '<div id="app" data-page="$escaped"></div>';
    }
    return '<div id="app" data-page="$escaped">$body</div>';
  }

  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  static Map<String, dynamic>? _consumeFlash(EngineContext ctx) {
    try {
      final data = ctx.getSession<Map<String, dynamic>>(_flashKey);
      if (data != null) {
        ctx.removeSession(_flashKey);
      }
      return data;
    } catch (_) {
      final data = ctx.getContextData<Map<String, dynamic>>(_flashKey);
      if (data != null) {
        ctx.setContextData(_flashKey, null);
      }
      return data;
    }
  }

  static Map<String, dynamic>? _consumeErrors(
    EngineContext ctx,
    String? errorBag,
  ) {
    Map<String, dynamic>? errors;
    try {
      errors = ctx.getSession<Map<String, dynamic>>(_errorsKey);
      if (errors != null) {
        ctx.removeSession(_errorsKey);
      }
    } catch (_) {
      errors = ctx.getContextData<Map<String, dynamic>>(_errorsKey);
      if (errors != null) {
        ctx.setContextData(_errorsKey, null);
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

  static InertiaConfig? _resolveInertiaConfig(EngineContext ctx) {
    if (!ctx.container.has<InertiaConfig>()) {
      return null;
    }
    try {
      return ctx.container.get<InertiaConfig>();
    } catch (_) {
      return null;
    }
  }

  static String _requestUrl(Uri uri, {HttpHeaders? headers}) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    final prefix = headers?.value('x-forwarded-prefix');
    final resolvedPath = _applyForwardedPrefix(path, prefix);
    if (uri.hasQuery) {
      return '$resolvedPath?${uri.query}';
    }
    return resolvedPath;
  }

  static String _applyForwardedPrefix(String path, String? prefix) {
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
}
