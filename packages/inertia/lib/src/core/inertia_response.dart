library;

import 'dart:convert';

import 'inertia_headers.dart';
import 'page_data.dart';

/// Defines the response payload for Inertia requests.
///
/// Use [InertiaResponse.json] for JSON responses and
/// [InertiaResponse.html] for initial HTML visits.
///
/// ```dart
/// final response = InertiaResponse.json(page);
/// ```
class InertiaResponse {
  /// Creates a response with the given [page] and metadata.
  const InertiaResponse({
    required this.page,
    this.statusCode = 200,
    this.headers = const {},
    this.html,
  });

  /// Creates a JSON response for Inertia requests.
  ///
  /// ```dart
  /// final response = InertiaResponse.json(page, statusCode: 201);
  /// ```
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

  /// Creates an HTML response for initial visits.
  ///
  /// ```dart
  /// final response = InertiaResponse.html(page, '<div id="app"></div>');
  /// ```
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

  /// Creates a location response for version mismatches.
  ///
  /// ```dart
  /// final response = InertiaResponse.location('/login');
  /// ```
  factory InertiaResponse.location(String url) {
    return InertiaResponse(
      page: PageData(component: '', props: {}, url: url),
      statusCode: 409,
      headers: {InertiaHeaders.inertiaLocation: url},
    );
  }

  /// The page data for this response.
  final PageData page;

  /// The HTTP status code for the response.
  final int statusCode;

  /// The headers to include in the response.
  final Map<String, String> headers;

  /// The optional HTML body for initial visits.
  final String? html;

  /// Converts [page] to a JSON-serializable map.
  Map<String, dynamic> toJson() => page.toJson();

  /// Encodes [page] to a JSON string.
  String toJsonString() => jsonEncode(page.toJson());

  /// Whether this response is an Inertia JSON response.
  bool get isInertia => headers[InertiaHeaders.inertia] == 'true';
}
