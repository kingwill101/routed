import 'dart:convert';
import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';

import 'inertia_utils.dart';

export 'middleware/routed_inertia_middleware.dart';
export 'middleware/inertia_encrypt_history_middleware.dart';
export 'package:inertia_dart/inertia_dart.dart'
    show
        EncryptHistoryMiddleware,
        ErrorHandlingMiddleware,
        InertiaViteAssets,
        InertiaViteAssetTags,
        InertiaMiddleware,
        PageData,
        RedirectMiddleware,
        SsrResponse,
        SharedDataMiddleware,
        VersionMiddleware;
export 'engine_context_inertia.dart';
export 'config/inertia_config.dart';
export 'provider/inertia_provider.dart';

/// Routed integration for Inertia responses.
class RoutedInertia {
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

  /// Render an Inertia response using the current [EngineContext].
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
    final flatHeaders = extractHttpHeaders(ctx.headers);
    final request = InertiaRequest(
      headers: flatHeaders,
      url: ctx.requestedUri.toString(),
      method: ctx.method,
    );
    final config = resolveInertiaConfig(ctx);

    final errors = consumeErrors(ctx, request.errorBag);
    final mergedProps = <String, dynamic>{
      if (errors != null) 'errors': AlwaysProp(() => errors),
      ...props,
    };

    final context = request.createContext();

    final flash = consumeFlash(ctx);
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
      url: url ?? inertiaRequestUrl(ctx.requestedUri, headers: ctx.headers),
      context: context,
      version: resolvedVersion,
      encryptHistory: resolvedEncryptHistory,
      clearHistory: clearHistory,
      flash: flash,
      cache: cache,
    );

    if (request.isInertia) {
      final inertiaResponse = InertiaResponse.json(page);
      for (final entry in inertiaResponse.headers.entries) {
        ctx.setHeader(entry.key, entry.value);
      }
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

  static String _defaultTemplateRenderer(PageData page, SsrResponse? ssr) {
    final json = jsonEncode(page.toJson());
    final escaped = escapeInertiaHtml(json);
    final body = ssr?.body ?? '';
    if (body.isEmpty) {
      return '<div id="app" data-page="$escaped"></div>';
    }
    return '<div id="app" data-page="$escaped">$body</div>';
  }
}
