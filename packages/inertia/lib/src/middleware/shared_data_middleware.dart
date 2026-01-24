import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Middleware that injects shared props into every Inertia response
class SharedDataMiddleware extends InertiaMiddleware {
  SharedDataMiddleware({required this.sharedData});
  final Map<String, dynamic> Function(InertiaRequest request) sharedData;

  @override
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
