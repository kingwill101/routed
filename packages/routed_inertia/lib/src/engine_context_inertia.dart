import 'dart:convert' as convert;

import 'package:inertia_dart/inertia.dart';
import 'package:routed/routed.dart';

/// Inertia helper methods on [EngineContext].
extension EngineContextInertia on EngineContext {
  static const String _sharedKey = 'inertia.shared';
  static const String _encryptHistoryKey = 'inertia.encryptHistory';
  static const String _clearHistoryKey = 'inertia.clearHistory';

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

    final sharedProps = _sharedProps().all();
    final mergedProps = <String, dynamic>{...sharedProps, ...props};

    final context = PropertyContext(
      headers: headers,
      isPartialReload: requestedProps.isNotEmpty,
      requestedProps: requestedProps,
    );

    final encryptHistoryValue =
        encryptHistory ?? getContextData<bool>(_encryptHistoryKey) ?? false;
    final clearHistoryValue = clearHistory ?? _consumeClearHistoryFlag();

    final page = InertiaResponseFactory().buildPageData(
      component: component,
      props: mergedProps,
      url: url ?? requestedUri.toString(),
      context: context,
      version: version,
      encryptHistory: encryptHistoryValue,
      clearHistory: clearHistoryValue,
    );

    if (isInertia) {
      setHeader(InertiaHeaders.inertia, 'true');
      setHeader(InertiaHeaders.inertiaVary, InertiaHeaders.inertia);
      return json(page.toJson());
    }

    SsrResponse? ssrResponse;
    if (ssrEnabled && ssrGateway != null) {
      try {
        final pageJson = convert.jsonEncode(page.toJson());
        ssrResponse = await ssrGateway.render(pageJson);
      } catch (error, stack) {
        if (onSsrError != null) {
          onSsrError(error, stack);
        }
      }
    }

    if (templateName != null || templateContent != null) {
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
        templateName: templateName,
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

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}
