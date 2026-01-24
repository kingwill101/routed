import 'dart:convert';

import 'headers.dart';
import 'page_data.dart';

/// Represents an Inertia response payload
class InertiaResponse {
  const InertiaResponse({
    required this.page,
    this.statusCode = 200,
    this.headers = const {},
    this.html,
  });

  /// Create a JSON response for Inertia requests
  factory InertiaResponse.json(PageData page, {int statusCode = 200}) {
    return InertiaResponse(
      page: page,
      statusCode: statusCode,
      headers: {
        InertiaHeaders.inertia: 'true',
        InertiaHeaders.inertiaVary: InertiaHeaders.inertia,
        'Content-Type': 'application/json',
      },
    );
  }

  /// Create an HTML response for initial visits
  factory InertiaResponse.html(
    PageData page,
    String html, {
    int statusCode = 200,
  }) {
    return InertiaResponse(
      page: page,
      html: html,
      statusCode: statusCode,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  /// Create a location response for version mismatches
  factory InertiaResponse.location(String url) {
    return InertiaResponse(
      page: PageData(component: '', props: {}, url: url),
      statusCode: 409,
      headers: {InertiaHeaders.inertiaLocation: url},
    );
  }

  /// The page data for the response
  final PageData page;

  /// Response status code
  final int statusCode;

  /// Response headers
  final Map<String, String> headers;

  /// Optional HTML template content for initial visits
  final String? html;

  /// Convert the page data to JSON map
  Map<String, dynamic> toJson() => page.toJson();

  /// Encode the page data as JSON string
  String toJsonString() => jsonEncode(page.toJson());

  /// Whether this is an Inertia JSON response
  bool get isInertia => headers[InertiaHeaders.inertia] == 'true';
}
