import 'dart:io';

import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';

/// Routed middleware for Inertia request handling
class RoutedInertiaMiddleware {
  RoutedInertiaMiddleware({required this.versionResolver});
  final String Function() versionResolver;

  Future<Response> call(EngineContext ctx, Next next) async {
    final headers = _extractHeaders(ctx.headers);
    final isInertia = InertiaHeaderUtils.isInertiaRequest(headers);
    final requestVersion = headers[InertiaHeaders.inertiaVersion] ?? '';
    final currentVersion = versionResolver();

    if (isInertia &&
        currentVersion.isNotEmpty &&
        requestVersion != currentVersion) {
      ctx.status(HttpStatus.conflict);
      ctx.setHeader(
        InertiaHeaders.inertiaLocation,
        ctx.requestedUri.toString(),
      );
      return ctx.response;
    }

    final response = await next();
    if (!isInertia) return response;

    final method = ctx.method.toUpperCase();
    final shouldRewrite =
        (method == 'PUT' || method == 'PATCH' || method == 'DELETE') &&
        response.statusCode == HttpStatus.found;
    if (shouldRewrite) {
      response.statusCode = HttpStatus.seeOther;
    }

    return response;
  }

  static Map<String, String> _extractHeaders(HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      if (values.isNotEmpty) {
        result[name] = values.first;
      }
    });
    return result;
  }
}
