import 'package:test/test.dart';

/// Fluent assertions for Inertia responses
class AssertableInertia {
  AssertableInertia(this.page);
  final Map<String, dynamic> page;

  Map<String, dynamic> get props =>
      (page['props'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  AssertableInertia component(String expected) {
    expect(
      page['component'],
      equals(expected),
      reason: 'Unexpected Inertia page component.',
    );
    return this;
  }

  AssertableInertia url(String expected) {
    expect(
      page['url'],
      equals(expected),
      reason: 'Unexpected Inertia page url.',
    );
    return this;
  }

  AssertableInertia version(String expected) {
    expect(
      page['version'],
      equals(expected),
      reason: 'Unexpected Inertia asset version.',
    );
    return this;
  }

  AssertableInertia where(String path, dynamic expected) {
    final actual = _getPathValue(props, path);
    expect(actual, equals(expected), reason: 'Unexpected value for $path.');
    return this;
  }

  AssertableInertia has(String path) {
    final actual = _getPathValue(props, path, allowMissing: true);
    expect(actual != null, isTrue, reason: 'Missing prop $path.');
    return this;
  }

  AssertableInertia missing(String path) {
    final actual = _getPathValue(props, path, allowMissing: true);
    expect(actual == null, isTrue, reason: 'Prop $path should be missing.');
    return this;
  }

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
