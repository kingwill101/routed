library;

import 'package:test/test.dart';

/// Provides fluent assertions for Inertia page payloads.
///
/// ```dart
/// response.assertInertia((page) {
///   page.component('Dashboard').has('user.name');
/// });
/// ```
class AssertableInertia {
  /// Creates an assertion helper for an Inertia page payload.
  AssertableInertia(this.page);

  /// The raw page payload.
  final Map<String, dynamic> page;

  /// The props map extracted from [page].
  Map<String, dynamic> get props =>
      (page['props'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  /// Asserts the page component matches [expected].
  AssertableInertia component(String expected) {
    expect(
      page['component'],
      equals(expected),
      reason: 'Unexpected Inertia page component.',
    );
    return this;
  }

  /// Asserts the page URL matches [expected].
  AssertableInertia url(String expected) {
    expect(
      page['url'],
      equals(expected),
      reason: 'Unexpected Inertia page url.',
    );
    return this;
  }

  /// Asserts the asset version matches [expected].
  AssertableInertia version(String expected) {
    expect(
      page['version'],
      equals(expected),
      reason: 'Unexpected Inertia asset version.',
    );
    return this;
  }

  /// Asserts the prop at [path] matches [expected].
  AssertableInertia where(String path, dynamic expected) {
    final actual = _getPathValue(props, path);
    expect(actual, equals(expected), reason: 'Unexpected value for $path.');
    return this;
  }

  /// Asserts that a prop exists at [path].
  AssertableInertia has(String path) {
    final actual = _getPathValue(props, path, allowMissing: true);
    expect(actual != null, isTrue, reason: 'Missing prop $path.');
    return this;
  }

  /// Asserts that a prop is missing at [path].
  AssertableInertia missing(String path) {
    final actual = _getPathValue(props, path, allowMissing: true);
    expect(actual == null, isTrue, reason: 'Prop $path should be missing.');
    return this;
  }

  /// Returns the nested value at [path], or fails the test if missing.
  dynamic _getPathValue(
    Map<String, dynamic> data,
    String path, {
    bool allowMissing = false,
  }) {
    dynamic current = data;
    for (final segment in path.split('.')) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        if (allowMissing) return null;
        fail('Path "$path" does not exist in props.');
      }
    }
    return current;
  }
}
