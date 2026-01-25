library;

import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Injects shared props into every Inertia response.
///
/// ```dart
/// final middleware = SharedDataMiddleware(
///   sharedData: (_) => {'appName': 'Inertia'},
/// );
/// ```
class SharedDataMiddleware extends InertiaMiddleware {
  /// Creates a middleware that appends shared props.
  SharedDataMiddleware({required this.sharedData});

  /// Provides shared props for the given [InertiaRequest].
  final Map<String, dynamic> Function(InertiaRequest request) sharedData;

  @override
  /// Merges shared props into the response page props.
  Future<InertiaResponse> handle(
    InertiaRequest request,
    InertiaHandler next,
  ) async {
    final response = await next(request);
    final shared = sharedData(request);

    if (shared.isEmpty) return response;

    final mergedProps = <String, dynamic>{}
      ..addAll(shared)
      ..addAll(response.page.props);

    final updatedPage = response.page.copyWith(props: mergedProps);
    return InertiaResponse(
      page: updatedPage,
      statusCode: response.statusCode,
      headers: response.headers,
      html: response.html,
    );
  }
}
