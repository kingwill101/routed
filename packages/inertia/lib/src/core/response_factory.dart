import '../property_context.dart';
import '../properties/property_resolver.dart';
import 'inertia_response.dart';
import 'page_data.dart';

/// Factory for building Inertia responses
class InertiaResponseFactory {
  /// Build a page data payload with resolved props
  PageData buildPageData({
    required String component,
    required Map<String, dynamic> props,
    required String url,
    required PropertyContext context,
    String version = '',
    bool encryptHistory = false,
    bool clearHistory = false,
  }) {
    final isPartialForComponent =
        context.isPartialReload && context.partialComponent == component;
    final effectiveContext = isPartialForComponent
        ? context
        : PropertyContext(
            headers: context.headers,
            isPartialReload: false,
            requestedProps: const [],
            requestedDeferredGroups: const [],
            resetKeys: const [],
            onceKey: context.onceKey,
            shouldIncludeProp: context.shouldIncludeProp,
          );

    final result = PropertyResolver.resolve(props, effectiveContext);

    return PageData(
      component: component,
      props: result.props,
      url: url,
      version: version,
      encryptHistory: encryptHistory,
      clearHistory: clearHistory,
      deferredProps: result.deferredProps.isEmpty ? null : result.deferredProps,
      mergeProps: result.mergeProps.isEmpty ? null : result.mergeProps,
    );
  }

  /// Build an Inertia JSON response
  InertiaResponse jsonResponse({
    required String component,
    required Map<String, dynamic> props,
    required String url,
    required PropertyContext context,
    String version = '',
    bool encryptHistory = false,
    bool clearHistory = false,
    int statusCode = 200,
  }) {
    final page = buildPageData(
      component: component,
      props: props,
      url: url,
      context: context,
      version: version,
      encryptHistory: encryptHistory,
      clearHistory: clearHistory,
    );

    return InertiaResponse.json(page, statusCode: statusCode);
  }
}
