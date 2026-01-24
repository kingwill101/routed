import 'package:server_testing/server_testing.dart';

import '../core/headers.dart';
import 'assertable_inertia.dart';

/// Extensions for asserting Inertia responses
extension InertiaTestExtensions on TestResponse {
  /// Assert this response is an Inertia response
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
