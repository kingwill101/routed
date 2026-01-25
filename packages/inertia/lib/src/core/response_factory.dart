library;

import '../property_context.dart';
import '../properties/property_resolver.dart';
import 'inertia_response.dart';
import 'page_data.dart';

/// Builds Inertia page payloads and responses.
///
/// This factory resolves props based on [PropertyContext] and returns either a
/// [PageData] or a ready [InertiaResponse].
///
/// ```dart
/// final factory = InertiaResponseFactory();
/// final page = factory.buildPageData(
///   component: 'Dashboard',
///   props: {'user': user},
///   url: '/dashboard',
///   context: context,
/// );
/// ```
class InertiaResponseFactory {
  /// Builds a [PageData] payload with resolved props.
  ///
  /// This handles partial reloads, deferred props, merge props, and history
  /// flags.
  PageData buildPageData({
    required String component,
    required Map<String, dynamic> props,
    required String url,
    required PropertyContext context,
    String version = '',
    bool encryptHistory = false,
    bool clearHistory = false,
    Map<String, dynamic>? flash,
    List<int>? cache,
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
      deepMergeProps: result.deepMergeProps.isEmpty
          ? null
          : result.deepMergeProps,
      prependProps: result.prependProps.isEmpty ? null : result.prependProps,
      matchPropsOn: result.matchPropsOn.isEmpty ? null : result.matchPropsOn,
      scrollProps: result.scrollProps.isEmpty ? null : result.scrollProps,
      onceProps: result.onceProps.isEmpty ? null : result.onceProps,
      flash: flash,
      cache: cache,
    );
  }

  /// Builds an Inertia JSON response with resolved props.
  ///
  /// ```dart
  /// final response = factory.jsonResponse(
  ///   component: 'Home',
  ///   props: {'title': 'Inertia'},
  ///   url: '/',
  ///   context: context,
  /// );
  /// ```
  InertiaResponse jsonResponse({
    required String component,
    required Map<String, dynamic> props,
    required String url,
    required PropertyContext context,
    String version = '',
    bool encryptHistory = false,
    bool clearHistory = false,
    Map<String, dynamic>? flash,
    List<int>? cache,
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
      flash: flash,
      cache: cache,
    );

    return InertiaResponse.json(page, statusCode: statusCode);
  }
}
