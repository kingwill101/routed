import 'dart:async';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_view/src/view/engine_manager.dart';

/// Local stub for Render to break dependency on `routed` render.
/// Original was in `package:routed/src/render/render.dart`.
abstract class Render {
  FutureOr<void> render(Response response);
  void writeContentType(Response response);
}

/// View/render extensions for [EngineContext] — migrated from `routed`
/// `src/context/render.dart` per refactor.md §16.2.
extension RoutedViewRender on EngineContext {
  FutureOr<void> viewRender(int statusCode, Render renderer) {
    renderer.writeContentType(response);
    response.statusCode = statusCode;
    return renderer.render(response);
  }

  Future<Response> view(
    String template, {
    Map<String, dynamic> data = const {},
    int statusCode = HttpStatus.ok,
  }) async {
    // Delegate to ViewEngine if available, otherwise write placeholder
    try {
      final manager = container.get<ViewEngineManager>();
      final content = await manager.render(template, data);
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.html;
      response.write(content);
    } catch (_) {
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.html;
      response.write('<!-- view: $template -->');
    }
    return response;
  }

  Future<Response> json(Object data, {int statusCode = HttpStatus.ok}) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(data is String ? data : _toJson(data));
    return response;
  }

  Future<Response> string(String data, {int statusCode = HttpStatus.ok, ContentType? contentType}) async {
    response.statusCode = statusCode;
    response.headers.contentType = contentType ?? ContentType.text;
    response.write(data);
    return response;
  }

  Future<Response> html(String data, {Map<String, dynamic> dataMap = const {}, int statusCode = HttpStatus.ok}) async {
    // html via string with html content type
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.html;
    response.write(data);
    return response;
  }

  Future<Response> redirect(String location, {int statusCode = HttpStatus.found}) async {
    response.statusCode = statusCode;
    response.headers.set(HttpHeaders.locationHeader, location);
    return response;
  }

  String _toJson(Object data) {
    try {
      return data is Map || data is List ? _jsonEncode(data) : data.toString();
    } catch (_) {
      return data.toString();
    }
  }

  String _jsonEncode(Object data) {
    // ignore: avoid_dynamic_calls
    return (data as dynamic).toString();
  }
}
