library;

import 'inertia_prop.dart';

/// Provides shared mixin behavior for merge, defer, and once props.
///
/// These mixins are used by property implementations to configure behavior
/// in a fluent style.
///
/// ```dart
/// final prop = MergeProp(() => items).append('items', 'id');
/// ```
mixin MergesProps implements MergeableProp {
  bool _merge = false;
  bool _deepMerge = false;
  bool _append = true;
  final List<String> _appendsAtPaths = [];
  final List<String> _prependsAtPaths = [];
  final List<String> _matchOn = [];

  /// Enables or disables merge behavior.
  void configureMerge([bool value = true]) {
    _merge = value;
  }

  /// Enables or disables deep merge behavior.
  void configureDeepMerge([bool value = true]) {
    _deepMerge = value;
    _merge = value ? true : _merge;
  }

  /// Configures match-on keys from a string or string iterable.
  ///
  /// #### Throws
  /// - [ArgumentError] if [value] is not a string or iterable of strings.
  void configureMatchOn(Object? value) {
    if (value == null) return;
    if (value is String) {
      if (!_matchOn.contains(value)) {
        _matchOn.add(value);
      }
      return;
    }
    if (value is Iterable<String>) {
      for (final item in value) {
        if (!_matchOn.contains(item)) {
          _matchOn.add(item);
        }
      }
      return;
    }
    throw ArgumentError('matchOn must be a String or Iterable<String>.');
  }

  /// Appends merge paths or toggles root append behavior.
  ///
  /// #### Throws
  /// - [ArgumentError] if [path] is not a bool, string, or iterable of strings.
  void append([Object? path, String? matchOn]) {
    if (path == null) {
      _append = true;
      return;
    }
    if (path is bool) {
      _append = path;
      return;
    }
    if (path is String) {
      if (!_appendsAtPaths.contains(path)) {
        _appendsAtPaths.add(path);
      }
      if (matchOn != null) {
        final key = '$path.$matchOn';
        if (!_matchOn.contains(key)) {
          _matchOn.add(key);
        }
      }
      return;
    }
    if (path is Iterable<String>) {
      for (final item in path) {
        append(item);
      }
      return;
    }
    throw ArgumentError(
      'append path must be bool, String, or Iterable<String>.',
    );
  }

  /// Prepends merge paths or toggles root prepend behavior.
  ///
  /// #### Throws
  /// - [ArgumentError] if [path] is not a bool, string, or iterable of strings.
  void prepend([Object? path, String? matchOn]) {
    if (path == null) {
      _append = false;
      return;
    }
    if (path is bool) {
      _append = !path;
      return;
    }
    if (path is String) {
      if (!_prependsAtPaths.contains(path)) {
        _prependsAtPaths.add(path);
      }
      if (matchOn != null) {
        final key = '$path.$matchOn';
        if (!_matchOn.contains(key)) {
          _matchOn.add(key);
        }
      }
      return;
    }
    if (path is Iterable<String>) {
      for (final item in path) {
        prepend(item);
      }
      return;
    }
    throw ArgumentError(
      'prepend path must be bool, String, or Iterable<String>.',
    );
  }

  @override
  /// Whether this prop should be merged.
  bool get shouldMerge => _merge;

  @override
  /// Whether this prop should be merged deeply.
  bool get shouldDeepMerge => _deepMerge;

  @override
  /// Whether appends happen at the root.
  bool get appendsAtRoot =>
      _append && _appendsAtPaths.isEmpty && _prependsAtPaths.isEmpty;

  @override
  /// Whether prepends happen at the root.
  bool get prependsAtRoot =>
      !_append && _appendsAtPaths.isEmpty && _prependsAtPaths.isEmpty;

  @override
  /// The configured append paths.
  List<String> get appendsAtPaths => List.unmodifiable(_appendsAtPaths);

  @override
  /// The configured prepend paths.
  List<String> get prependsAtPaths => List.unmodifiable(_prependsAtPaths);

  @override
  /// The configured match-on keys.
  List<String> get matchesOn => List.unmodifiable(_matchOn);
}

/// Shared deferral configuration for deferrable props.
mixin DefersProps implements DeferrableProp {
  bool _deferred = false;
  String _group = 'default';

  /// Enables deferral and optionally sets the [group].
  void configureDeferred({bool deferred = true, String? group}) {
    _deferred = deferred;
    if (group != null) {
      _group = group;
    }
  }

  @override
  /// Whether the prop should be deferred.
  bool get shouldDefer => _deferred;

  @override
  /// The deferred group name.
  String get group => _group;
}

/// Shared configuration for once props.
mixin ResolvesOnce implements OnceableProp {
  bool _once = false;
  bool _refresh = false;
  String? _key;
  Duration? _ttl;

  /// Enables once resolution and configures optional metadata.
  void configureOnce({
    bool once = true,
    String? key,
    Duration? ttl,
    bool refresh = false,
  }) {
    _once = once;
    if (key != null) {
      _key = key;
    }
    if (ttl != null) {
      _ttl = ttl;
    }
    _refresh = refresh;
  }

  /// Enables or disables refresh behavior.
  void refresh([bool value = true]) {
    _refresh = value;
  }

  /// Sets the once key.
  void as(String key) {
    _key = key;
  }

  /// Sets the time-to-live for once values.
  void until(Duration ttl) {
    _ttl = ttl;
  }

  @override
  /// Whether this prop should resolve once.
  bool get shouldResolveOnce => _once;

  @override
  /// Whether this prop should refresh.
  bool get shouldRefresh => _refresh;

  @override
  /// The key used for once tracking, if any.
  String? get onceKey => _key;

  @override
  /// The configured time-to-live, if any.
  Duration? get ttl => _ttl;
}
