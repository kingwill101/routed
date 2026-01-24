import 'headers.dart';

/// Inertia page data structure
class PageData {
  const PageData({
    required this.component,
    required this.props,
    required this.url,
    this.version = '',
    this.encryptHistory = false,
    this.clearHistory = false,
    this.deferredProps,
    this.mergeProps,
  });

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
  final String component;
  final Map<String, dynamic> props;
  final String url;
  final String version;
  final bool encryptHistory;
  final bool clearHistory;
  final Map<String, List<String>>? deferredProps;
  final List<String>? mergeProps;

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
    };

    // Remove null/empty values for cleaner JSON
    data.removeWhere(
      (key, value) =>
          value == null || value == '' || (value is List && value.isEmpty),
    );

    return data;
  }

  static bool _parseHistoryFlag(Map<String, String> headers, String flag) {
    final historyHeader = headers['X-Inertia-History'];
    if (historyHeader == null) return false;

    return historyHeader.toLowerCase().contains(flag);
  }

  /// Copy PageData with updated fields
  PageData copyWith({
    String? component,
    Map<String, dynamic>? props,
    String? url,
    String? version,
    bool? encryptHistory,
    bool? clearHistory,
    Map<String, List<String>>? deferredProps,
    List<String>? mergeProps,
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
    );
  }
}
