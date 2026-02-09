import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';

/// Routed middleware for Inertia request handling.
class RoutedInertiaMiddleware {
  RoutedInertiaMiddleware({required this.versionResolver});
  final String Function() versionResolver;

  Future<Response> call(EngineContext ctx, Next next) async {
    final flatHeaders = extractHttpHeaders(ctx.headers);
    final request = InertiaRequest(
      headers: flatHeaders,
      url: ctx.requestedUri.toString(),
      method: ctx.method,
    );
    final currentVersion = versionResolver();

    if (request.isInertia &&
        currentVersion.isNotEmpty &&
        (request.version ?? '') != currentVersion) {
      ctx.setHeader(
        InertiaHeaders.inertiaLocation,
        ctx.requestedUri.toString(),
      );
      return ctx.string('', statusCode: HttpStatus.conflict);
    }

    final response = await next();
    if (!request.isInertia) return response;

    final method = ctx.method.toUpperCase();
    final shouldRewrite =
        (method == 'PUT' || method == 'PATCH' || method == 'DELETE') &&
        response.statusCode == HttpStatus.found;
    if (shouldRewrite) {
      response.statusCode = HttpStatus.seeOther;
    }

    return response;
  }
}
