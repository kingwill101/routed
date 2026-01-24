import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Middleware that checks Inertia asset version
class VersionMiddleware extends InertiaMiddleware {
  VersionMiddleware({required this.versionResolver, this.locationResolver});
  final String Function() versionResolver;
  final String Function(InertiaRequest request)? locationResolver;

  @override
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
