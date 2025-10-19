import 'dart:io';
import 'dart:typed_data';

import 'package:class_view/class_view.dart';
import 'package:routed/routed.dart' as routed;

/// An adapter for the Routed HTTP server framework.
class RoutedAdapter implements ViewAdapter {
  final routed.EngineContext _context;
  final Map<String, String> _routeParams;

  RoutedAdapter(this._context, [Map<String, String>? routeParams])
    : _routeParams = routeParams ?? {};

  /// Exposes the underlying Routed [EngineContext] for advanced scenarios
  /// like cache access or config inspection.
  routed.EngineContext get context => _context;

  @override
  Future<String> getMethod() async => _context.method;

  @override
  Future<Uri> getUri() async => _context.uri;

  @override
  Future<String?> getParam(String name) async {
    return (await getParams())[name];
  }

  @override
  Future<Map<String, String>> getParams() async {
    final params = <String, String>{
      ..._context.params.cast(),
      ..._routeParams,
      ...(await getQueryParams()),
    };
    return params;
  }

  @override
  Future<Map<String, String>> getQueryParams() async {
    return _context.queryCache.cast();
  }

  @override
  Future<Map<String, String>> getRouteParams() async {
    return Map<String, String>.from({
      ..._context.params.cast(),
      ..._routeParams,
    });
  }

  @override
  Future<Map<String, String>> getHeaders() async {
    final headers = <String, String>{};
    _context.headers.forEach((key, value) {
      headers[key.toLowerCase()] = value.join(', ');
    });
    return headers;
  }

  @override
  Future<String?> getHeader(String name) async {
    final values =
        _context.headers[name.toLowerCase()] ?? _context.headers[name];
    return values?.isNotEmpty == true ? values!.join(', ') : null;
  }

  @override
  Future<String> getBody() async {
    final bodyContent = await _context.request.body();
    return bodyContent.toString();
  }

  @override
  Future<Map<String, dynamic>> getJsonBody() async {
    try {
      Map<String, dynamic> jsonBody = {};
      await _context.bindJSON(jsonBody);
      return jsonBody;
    } catch (e) {
      throw FormatException('Invalid JSON in request body: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getFormData() async {
    Map<String, dynamic> formData = {};
    _context.bind(formData);
    return formData;
  }

  @override
  Future<FormFile?> getUploadedFile(String fieldName) async {
    final files = await getUploadedFiles();
    try {
      return files.firstWhere((file) => file.name == fieldName);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<FormFile>> getUploadedFiles() async {
    List<FormFile>? uploadedFiles;

    final form = await _context.multipartForm;
    uploadedFiles = await Future.wait(
      form.files.map((file) async {
        final bytes = await File(file.path).readAsBytes();
        return _RoutedFormFile(
          name: file.name,
          size: file.size,
          contentType: file.contentType,
          content: Uint8List.fromList(bytes),
        );
      }),
    );

    return uploadedFiles;
  }

  @override
  Future<bool> hasFile(String fieldName) async {
    final files = await getUploadedFiles();
    return files.any((file) => file.name == fieldName);
  }

  // === Response Operations ===

  @override
  Future<void> setStatusCode(int code) async {
    _context.status(code);
  }

  @override
  Future<void> setHeader(String name, String value) async {
    _context.setHeader(name, value);
  }

  @override
  Future<void> write(String body) async {
    _context.write(body);
  }

  @override
  Future<void> writeJson(
    Map<String, dynamic> data, {
    int statusCode = 200,
  }) async {
    _context.json(data, statusCode: statusCode);
  }

  @override
  Future<void> redirect(String url, {int statusCode = 302}) async {
    await _context.redirect(url, statusCode: statusCode);
  }

  @override
  Future<void> setup() async {}

  @override
  Future<void> teardown() async {}
}

/// Implementation of FormFile for Routed adapter
class _RoutedFormFile implements FormFile {
  @override
  String name;

  @override
  int size;

  @override
  String contentType;

  @override
  Uint8List content;

  _RoutedFormFile({
    required this.name,
    required this.size,
    required this.contentType,
    required this.content,
  });
}
