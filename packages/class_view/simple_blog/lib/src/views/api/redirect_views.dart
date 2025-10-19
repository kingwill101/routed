import 'package:class_view/class_view.dart';

/// Examples of RedirectView usage
///
/// Demonstrates:
/// - Permanent vs temporary redirects
/// - URL pattern redirects
/// - Query parameter preservation
/// - Conditional redirects

/// Redirect old URL patterns to new ones
class LegacyPostRedirectView extends RedirectView {
  @override
  bool get permanent => true; // 301 permanent redirect

  @override
  Future<String> getRedirectUrl() async {
    // Old pattern: /blog/post-title
    // New pattern: /posts/post-title
    final oldPath = await getParam('path');
    return '/posts/$oldPath';
  }
}

/// Redirect to post detail by ID, finding the slug
class PostIdRedirectView extends RedirectView {
  @override
  bool get permanent => false; // 302 temporary redirect

  @override
  Future<String> getRedirectUrl() async {
    final id = await getParam('id');

    // In real app, look up the post slug from ID
    // For now, just redirect to list
    if (id == null || id.isEmpty) {
      return '/posts';
    }

    // TODO: Look up actual slug from ID
    return '/posts/$id';
  }
}

/// Conditional redirect based on user state
class ConditionalRedirectView extends RedirectView {
  @override
  bool get permanent => false;

  @override
  Future<String> getRedirectUrl() async {
    // Example: Redirect to different pages based on authentication
    // final isAuthenticated = await checkAuth();
    final isAuthenticated = false; // Placeholder

    if (isAuthenticated) {
      return '/dashboard';
    } else {
      return '/login';
    }
  }
}

/// Redirect with query parameter preservation
class QueryPreservingRedirectView extends RedirectView {
  @override
  bool get permanent => false;

  @override
  Future<String> getRedirectUrl() async {
    // Preserve query parameters in redirect
    final params = await getParams();
    final queryString = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');

    final baseUrl = '/posts';
    return queryString.isEmpty ? baseUrl : '$baseUrl?$queryString';
  }
}

/// Chain redirects (redirect to redirect)
class RedirectChainView extends RedirectView {
  @override
  bool get permanent => false;

  @override
  Future<String> getRedirectUrl() async {
    final step = await getParam('step');

    switch (step) {
      case '1':
        return '/redirect?step=2';
      case '2':
        return '/redirect?step=3';
      case '3':
      default:
        return '/posts';
    }
  }
}

/// Smart redirect that chooses destination based on referrer
class SmartRedirectView extends RedirectView {
  @override
  bool get permanent => false;

  @override
  Future<String> getRedirectUrl() async {
    final referrer = await getHeader('Referer');
    final returnTo = await getParam('return_to');

    // Priority: explicit return_to > referrer > default
    if (returnTo != null && returnTo.isNotEmpty) {
      return returnTo;
    }

    if (referrer != null && referrer.isNotEmpty) {
      // Validate referrer is from same domain
      if (referrer.contains('localhost') || referrer.contains('example.com')) {
        return referrer;
      }
    }

    return '/'; // Default fallback
  }
}
