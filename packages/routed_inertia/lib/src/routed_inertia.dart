import 'dart:convert';
import 'package:inertia_dart/inertia.dart';
import 'package:routed/routed.dart';

export 'middleware/routed_inertia_middleware.dart';
export 'engine_context_inertia.dart';

/// Routed integration for Inertia responses
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

  /// Render an Inertia response using the current EngineContext
  Future<Response> render(
    EngineContext ctx,
    String component,
    Map<String, dynamic> props, {
    String? url,
    String version = '',
    bool encryptHistory = false,
    bool clearHistory = false,
  }) async {
    final headers = _extractHeaders(ctx.headers);
    final isInertia = InertiaHeaderUtils.isInertiaRequest(headers);
    final requestedProps =
        InertiaHeaderUtils.getPartialData(headers) ?? const [];

    final context = PropertyContext(
      headers: headers,
      isPartialReload: requestedProps.isNotEmpty,
      requestedProps: requestedProps,
    );

    final page = responseFactory.buildPageData(
      component: component,
      props: props,
      url: url ?? ctx.requestedUri.toString(),
      context: context,
      version: version,
      encryptHistory: encryptHistory,
      clearHistory: clearHistory,
    );

    if (isInertia) {
      ctx.setHeader(InertiaHeaders.inertia, 'true');
      ctx.setHeader(InertiaHeaders.inertiaVary, InertiaHeaders.inertia);
      return ctx.json(page.toJson());
    }

    SsrResponse? ssrResponse;
    if (ssrEnabled && ssrGateway != null) {
      try {
        final pageJson = jsonEncode(page.toJson());
        ssrResponse = await ssrGateway!.render(pageJson);
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
}
