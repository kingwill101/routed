/// Test helpers for Inertia responses and headers.
///
/// ```dart
/// final headers = InertiaTestHelpers.createInertiaHeaders(version: '1.0.0');
/// ```
library;

import 'dart:convert';
import 'package:server_testing/server_testing.dart';

/// Utility helpers for Inertia tests using `server_testing`.
class InertiaTestHelpers {
  /// Creates basic Inertia headers for testing.
  static Map<String, String> createInertiaHeaders({
    String version = '',
    List<String>? partialData,
    String? partialComponent,
  }) {
    final headers = <String, String>{};
    headers['X-Inertia'] = 'true';

    if (version.isNotEmpty) {
      headers['X-Inertia-Version'] = version;
    }

    if (partialData != null) {
      headers['X-Inertia-Partial-Data'] = partialData.join(',');
    }

    if (partialComponent != null) {
      headers['X-Inertia-Partial-Component'] = partialComponent;
    }

    return headers;
  }

  /// Creates a mock JSON response for testing.
  static TestResponse createMockInertiaResponse({
    required String component,
    Map<String, dynamic>? props,
    String url = '/test',
    String version = '1.0',
    int statusCode = 200,
    Map<String, List<String>> headers = const {},
  }) {
    final pageData = {
      'component': component,
      'props': props ?? {},
      'url': url,
      'version': version,
    };

    return TestResponse(
      statusCode: statusCode,
      headers: {
        'content-type': ['application/json'],
        'X-Inertia': ['true'],
        ...headers,
      },
      bodyBytes: utf8.encode(jsonEncode(pageData)),
      uri: url,
    );
  }

  /// Asserts that [response] is an Inertia response.
  static void assertIsInertia(TestResponse response) {
    final values = response.headers['X-Inertia'] ?? const [];
    expect(
      values.contains('true'),
      isTrue,
      reason: 'Response should have X-Inertia header',
    );
  }

  /// Asserts that [response] uses [expectedComponent].
  static void assertComponent(TestResponse response, String expectedComponent) {
    assertIsInertia(response);

    final body = utf8.decode(response.bodyBytes);
    final pageData = jsonDecode(body) as Map<String, dynamic>;
    expect(
      pageData['component'],
      equals(expectedComponent),
      reason:
          'Expected component $expectedComponent but got ${pageData['component']}',
    );
  }

  /// Asserts that [response] includes the expected props.
  static void assertProps(
    TestResponse response,
    Map<String, dynamic> expectedProps,
  ) {
    assertIsInertia(response);

    final body = utf8.decode(response.bodyBytes);
    final pageData = jsonDecode(body) as Map<String, dynamic>;
    final actualProps = pageData['props'] as Map<String, dynamic>;

    expectedProps.forEach((key, expectedValue) {
      expect(
        actualProps,
        containsPair(key, expectedValue),
        reason:
            'Expected prop $key to equal $expectedValue but got ${actualProps[key]}',
      );
    });
  }

  /// Asserts that [response] has [expectedStatus].
  static void assertStatus(TestResponse response, int expectedStatus) {
    expect(
      response.statusCode,
      equals(expectedStatus),
      reason: 'Expected status $expectedStatus but got ${response.statusCode}',
    );
  }
}
