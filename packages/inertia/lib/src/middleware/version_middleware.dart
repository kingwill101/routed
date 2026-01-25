library;

import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Provides middleware to enforce asset version checks.
///
/// ```dart
/// final middleware = VersionMiddleware(
///   versionResolver: () => '1.0.0',
/// );
/// ```
class VersionMiddleware extends InertiaMiddleware {
  /// Creates a version-checking middleware.
  VersionMiddleware({required this.versionResolver, this.locationResolver});

  /// Resolves the current asset version.
  final String Function() versionResolver;

  /// Resolves the redirect location on version mismatch.
  final String Function(InertiaRequest request)? locationResolver;

  @override
  /// Returns a location response when the version mismatches.
  Future<InertiaResponse> handle(
    InertiaRequest request,
    InertiaHandler next,
  ) async {
    if (!request.isInertia) {
      return next(request);
    }

    final currentVersion = versionResolver();
    final requestVersion = request.version ?? '';
    if (currentVersion.isNotEmpty && requestVersion != currentVersion) {
      final location = locationResolver?.call(request) ?? request.url;
      return InertiaResponse.location(location);
    }

    return next(request);
  }
}
