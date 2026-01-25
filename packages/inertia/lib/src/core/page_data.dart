library;

import 'inertia_header_utils.dart';

/// Defines the Inertia page payload structure.
///
/// [PageData] is serialized to JSON and sent to the client during Inertia
/// visits.
///
/// ```dart
/// final page = PageData(
///   component: 'Dashboard',
///   props: {'user': {'name': 'Ada'}},
///   url: '/dashboard',
/// );
/// ```
class PageData {
  /// Creates a page payload with explicit values.
  const PageData({
    required this.component,
    required this.props,
    required this.url,
    this.version = '',
    this.encryptHistory = false,
    this.clearHistory = false,
    this.deferredProps,
    this.mergeProps,
    this.deepMergeProps,
    this.prependProps,
    this.matchPropsOn,
    this.scrollProps,
    this.onceProps,
    this.flash,
    this.cache,
  });

  /// Creates a page payload with version and history flags from [headers].
  ///
  /// ```dart
  /// final page = PageData.fromContext(
  ///   'Home',
  ///   {'title': 'Hello'},
  ///   '/',
  ///   headers,
  /// );
  /// ```
  factory PageData.fromContext(
    String component,
    Map<String, dynamic> props,
    String url,
    Map<String, String> headers,
  ) {
    return PageData(
      component: component,
      props: props,
      url: url,
      version: InertiaHeaderUtils.getVersion(headers) ?? '',
      encryptHistory: _parseHistoryFlag(headers, 'encrypt'),
      clearHistory: _parseHistoryFlag(headers, 'clear'),
    );
  }

  /// The component name to render on the client.
  final String component;

  /// The props data for the component.
  final Map<String, dynamic> props;

  /// The current URL for this visit.
  final String url;

  /// The asset version string used for cache-busting.
  final String version;

  /// Whether the client should encrypt history entries.
  final bool encryptHistory;

  /// Whether the client should clear history entries.
  final bool clearHistory;

  /// Deferred prop groups keyed by group name.
  final Map<String, List<String>>? deferredProps;

  /// Prop keys to merge shallowly on the client.
  final List<String>? mergeProps;

  /// Prop keys to merge deeply on the client.
  final List<String>? deepMergeProps;

  /// Prop keys to prepend when merging.
  final List<String>? prependProps;

  /// Prop keys to match on during merge operations.
  final List<String>? matchPropsOn;

  /// Scroll prop metadata keyed by prop name.
  final Map<String, Map<String, dynamic>>? scrollProps;

  /// Once prop metadata keyed by prop name.
  final Map<String, Map<String, dynamic>>? onceProps;

  /// Flash data to include with the response.
  final Map<String, dynamic>? flash;

  /// Cache headers to include for the response.
  final List<int>? cache;

  /// Converts this page payload to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    final data = {
      'component': component,
      'props': props,
      'url': url,
      'version': version,
      'encryptHistory': encryptHistory,
      'clearHistory': clearHistory,
      if (deferredProps != null && deferredProps!.isNotEmpty)
        'deferredProps': deferredProps,
      if (mergeProps != null && mergeProps!.isNotEmpty)
        'mergeProps': mergeProps,
      if (deepMergeProps != null && deepMergeProps!.isNotEmpty)
        'deepMergeProps': deepMergeProps,
      if (prependProps != null && prependProps!.isNotEmpty)
        'prependProps': prependProps,
      if (matchPropsOn != null && matchPropsOn!.isNotEmpty)
        'matchPropsOn': matchPropsOn,
      if (scrollProps != null && scrollProps!.isNotEmpty)
        'scrollProps': scrollProps,
      if (onceProps != null && onceProps!.isNotEmpty) 'onceProps': onceProps,
      if (flash != null && flash!.isNotEmpty) 'flash': flash,
      if (cache != null && cache!.isNotEmpty) 'cache': cache,
    };

    // Remove null/empty values for cleaner JSON
    data.removeWhere(
      (key, value) =>
          value == null || value == '' || (value is List && value.isEmpty),
    );

    return data;
  }

  /// Parses history flags from the `X-Inertia-History` header.
  static bool _parseHistoryFlag(Map<String, String> headers, String flag) {
    final historyHeader = headers['X-Inertia-History'];
    if (historyHeader == null) return false;

    return historyHeader.toLowerCase().contains(flag);
  }

  /// Returns a copy of this page payload with updated fields.
  ///
  /// ```dart
  /// final updated = page.copyWith(version: '2.0.0');
  /// ```
  PageData copyWith({
    String? component,
    Map<String, dynamic>? props,
    String? url,
    String? version,
    bool? encryptHistory,
    bool? clearHistory,
    Map<String, List<String>>? deferredProps,
    List<String>? mergeProps,
    List<String>? deepMergeProps,
    List<String>? prependProps,
    List<String>? matchPropsOn,
    Map<String, Map<String, dynamic>>? scrollProps,
    Map<String, Map<String, dynamic>>? onceProps,
    Map<String, dynamic>? flash,
    List<int>? cache,
  }) {
    return PageData(
      component: component ?? this.component,
      props: props ?? this.props,
      url: url ?? this.url,
      version: version ?? this.version,
      encryptHistory: encryptHistory ?? this.encryptHistory,
      clearHistory: clearHistory ?? this.clearHistory,
      deferredProps: deferredProps ?? this.deferredProps,
      mergeProps: mergeProps ?? this.mergeProps,
      deepMergeProps: deepMergeProps ?? this.deepMergeProps,
      prependProps: prependProps ?? this.prependProps,
      matchPropsOn: matchPropsOn ?? this.matchPropsOn,
      scrollProps: scrollProps ?? this.scrollProps,
      onceProps: onceProps ?? this.onceProps,
      flash: flash ?? this.flash,
      cache: cache ?? this.cache,
    );
  }
}
