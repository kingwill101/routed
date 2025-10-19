import 'dart:io' show HttpStatus;

import 'base.dart';

/// Generic RedirectView for clean redirects
///
/// A simple redirect view that users can extend for redirect functionality.
/// Supports permanent redirects, query string preservation, and dynamic URL generation.
///
/// Example usage:
/// ```dart
/// class LoginRedirectView extends RedirectView {
///   @override
///   String get redirectUrl => '/dashboard';
/// }
///
/// class DynamicRedirectView extends RedirectView {
///   @override
///   Future<String> getRedirectUrl() async {
///     final id = await getParam('id');
///     return '/posts/$id';
///   }
/// }
/// ```
abstract class RedirectView extends View {
  /// The URL to redirect to (override this for static redirects)
  String? get redirectUrl => null;

  /// Whether to make this a permanent redirect (301 vs 302)
  bool get permanent => false;

  /// Whether to preserve the query string in the redirect
  bool get preserveQueryString => false;

  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final url = await getRedirectUrl();
    final statusCode = permanent
        ? HttpStatus.movedPermanently
        : HttpStatus.found;
    await redirect(url, statusCode: statusCode);
  }

  /// Get the URL to redirect to (override for dynamic redirects)
  ///
  /// Override this method for dynamic URL generation:
  /// ```dart
  /// @override
  /// Future<String> getRedirectUrl() async {
  ///   final userId = await getParam('user_id');
  ///   return '/users/$userId/profile';
  /// }
  /// ```
  Future<String> getRedirectUrl() async {
    String url = redirectUrl ?? '';
    if (url.isEmpty) {
      throw Exception(
        'RedirectView requires either redirectUrl property or getRedirectUrl() override',
      );
    }

    if (preserveQueryString) {
      final uri = await getUri();
      final queryString = uri.query;
      if (queryString.isNotEmpty) {
        final separator = url.contains('?') ? '&' : '?';
        url = '$url$separator$queryString';
      }
    }

    return url;
  }
}
