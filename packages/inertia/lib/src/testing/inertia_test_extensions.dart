library;

import 'package:server_testing/server_testing.dart';

import '../core/inertia_headers.dart';
import 'assertable_inertia.dart';

/// Adds Inertia assertions to [TestResponse].
///
/// ```dart
/// response.assertInertia((page) {
///   page.component('Home');
/// });
/// ```
extension InertiaTestExtensions on TestResponse {
  /// Asserts this response is an Inertia response.
  void assertInertia([void Function(AssertableInertia inertia)? callback]) {
    final values = headers[InertiaHeaders.inertia] ?? const [];
    if (!values.contains('true')) {
      fail('Not a valid Inertia response.');
    }

    final page = json() as Map<String, dynamic>;
    final assertable = AssertableInertia(page);
    if (callback != null) {
      callback(assertable);
    }
  }
}
