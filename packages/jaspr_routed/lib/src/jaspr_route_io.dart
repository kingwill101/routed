import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/server.dart' as jaspr;
import 'package:routed/routed.dart';

import 'inherited_engine_context_io.dart';

typedef JasprComponentBuilder =
    FutureOr<Component> Function(EngineContext context);

/// Creates a Routed handler that renders the provided Jaspr [Component].
///
/// The builder receives the active [EngineContext] so applications can pull
/// request data, containers, or sessions when constructing the component tree.
Handler jasprRoute(JasprComponentBuilder builder) {
  final route = _JasprRoute(builder);
  return route.call;
}

class _JasprRoute {
  _JasprRoute(this._builder);

  final JasprComponentBuilder _builder;

  Future<Response> call(EngineContext ctx) async {
    final component = await _builder(ctx);
    final wrapped = InheritedEngineContext(context: ctx, child: component);

    final jasprRequest = await _toJasprRequest(ctx);
    final result = await jaspr.renderComponent(wrapped, request: jasprRequest);

    _applyResponse(ctx.response, result);
    return ctx.response;
  }

  Future<jaspr.Request> _toJasprRequest(EngineContext ctx) async {
    final headers = <String, String>{};
    ctx.request.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });

    final bodyBytes = await ctx.request.bytes;

    return jaspr.Request(
      ctx.request.method,
      ctx.request.requestedUri,
      headers: headers,
      context: {'routed.context': ctx},
      body: bodyBytes,
    );
  }

  void _applyResponse(
    Response response,
    ({int statusCode, String body, Map<String, List<String>> headers}) result,
  ) {
    response.statusCode = result.statusCode;

    result.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == HttpHeaders.transferEncodingHeader ||
          lower == HttpHeaders.contentLengthHeader) {
        // Let Dart compute transfer encoding & content length.
        return;
      }
      if (lower == HttpHeaders.setCookieHeader) {
        for (final value in values) {
          response.headers.add(name, value);
        }
      } else {
        response.headers.set(name, values.join(', '));
      }
    });

    response.write(result.body);
    response.close();
  }
}
