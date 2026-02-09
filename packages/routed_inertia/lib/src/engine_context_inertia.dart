import 'dart:convert' as convert;

import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';

import 'inertia_utils.dart';

/// Inertia helper methods on [EngineContext].
extension EngineContextInertia on EngineContext {
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
    bool includeAssets = true,
    void Function(Object error, StackTrace stack)? onSsrError,
    String Function(PageData page, SsrResponse? ssr)? htmlBuilder,
  }) async {
    final flatHeaders = extractHttpHeaders(headers);
    final request = InertiaRequest(
      headers: flatHeaders,
      url: requestedUri.toString(),
      method: method,
    );
    final config = resolveInertiaConfig(this);

    final sharedProps = _sharedProps().all();
    final errors = consumeErrors(this, request.errorBag);
    final mergedProps = <String, dynamic>{
      ...sharedProps,
      if (errors != null) 'errors': AlwaysProp(() => errors),
      ...props,
    };

    final context = request.createContext();

    final encryptHistoryValue =
        encryptHistory ??
        getContextData<bool>(InertiaKeys.encryptHistory) ??
        config?.history.encrypt ??
        false;
    final clearHistoryValue = clearHistory ?? consumeClearHistoryFlag(this);
    final flash = consumeFlash(this);
    final resolvedVersion = version.isEmpty
        ? (config?.resolveVersion() ?? '')
        : version;

    final page = await InertiaResponseFactory().buildPageDataAsync(
      component: component,
      props: mergedProps,
      url: url ?? inertiaRequestUrl(requestedUri, headers: headers),
      context: context,
      version: resolvedVersion,
      encryptHistory: encryptHistoryValue,
      clearHistory: clearHistoryValue,
      flash: flash,
      cache: cache,
    );

    if (request.isInertia) {
      final inertiaResponse = InertiaResponse.json(page);
      for (final entry in inertiaResponse.headers.entries) {
        setHeader(entry.key, entry.value);
      }
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
      InertiaViteAssetTags? assetTags;
      if (includeAssets) {
        assetTags = await resolveInertiaAssets(config);
      }
      final pageJson = convert.jsonEncode(page.toJson());
      final data = <String, dynamic>{
        'page': page.toJson(),
        'pageJson': pageJson,
        'pageJsonEscaped': escapeInertiaHtml(pageJson),
        'props': page.props,
        'component': page.component,
        'url': page.url,
        'version': page.version,
        if (ssrResponse != null)
          'ssr': {'body': ssrResponse.body, 'head': ssrResponse.head},
        if (ssrResponse != null) 'ssrBody': ssrResponse.body,
        if (ssrResponse != null) 'ssrHead': ssrResponse.head,
        if (assetTags != null) 'inertia_styles': assetTags.renderStyles(),
        if (assetTags != null) 'inertia_scripts': assetTags.renderScripts(),
        ...templateData,
      };

      return template(
        content: templateContent,
        templateName: resolvedTemplateName,
        data: data,
      );
    }

    final htmlContent =
        htmlBuilder?.call(page, ssrResponse) ??
        inertiaDefaultHtml(page, ssrResponse);
    return html(htmlContent);
  }

  InertiaSharedProps _sharedProps() {
    final existing = getContextData<InertiaSharedProps>(InertiaKeys.shared);
    if (existing != null) return existing;
    final created = InertiaSharedProps();
    setContextData(InertiaKeys.shared, created);
    return created;
  }

  /// Enable or disable history encryption for this request.
  void inertiaEncryptHistory([bool value = true]) {
    setContextData(InertiaKeys.encryptHistory, value);
  }

  /// Clear Inertia history for the next response.
  void inertiaClearHistory() {
    try {
      setSession(InertiaKeys.clearHistory, true);
    } catch (_) {
      setContextData(InertiaKeys.clearHistory, true);
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
      final existing =
          getSession<Map<String, dynamic>>(InertiaKeys.flash) ?? {};
      setSession(InertiaKeys.flash, {...existing, ...data});
    } catch (_) {
      final existing =
          getContextData<Map<String, dynamic>>(InertiaKeys.flash) ?? {};
      setContextData(InertiaKeys.flash, {...existing, ...data});
    }
  }

  /// Store validation errors for the next Inertia response.
  void inertiaErrors(Map<String, dynamic> errors, {String bag = 'default'}) {
    try {
      final existing =
          getSession<Map<String, dynamic>>(InertiaKeys.errors) ?? {};
      setSession(InertiaKeys.errors, {...existing, bag: errors});
    } catch (_) {
      final existing =
          getContextData<Map<String, dynamic>>(InertiaKeys.errors) ?? {};
      setContextData(InertiaKeys.errors, {...existing, bag: errors});
    }
  }
}
