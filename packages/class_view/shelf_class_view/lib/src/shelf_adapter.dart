import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:class_view/class_view.dart';
import 'package:shelf/shelf.dart' as shelf show Request, Response;
import 'package:shelf_multipart/shelf_multipart.dart';

/// Shelf implementation of ViewAdapter
///
/// This adapter bridges between Shelf's Request/Response system and our
/// framework-agnostic class views.
class ShelfAdapter implements ViewAdapter {
  final shelf.Request _request;
  final Map<String, String> _routeParams;
  final Map<String, String> _headers = {};
  final List<String> _body = [];
  int _statusCode = HttpStatus.ok;
  Map<String, dynamic>? _formData;
  List<FormFile>? _uploadedFiles;

  ShelfAdapter(this._request, [this._routeParams = const {}]);

  // === Request Information ===

  @override
  Future<String> getMethod() async => _request.method.toUpperCase();

  @override
  Future<Uri> getUri() async => _request.requestedUri;

  @override
  Future<String?> getParam(String name) async {
    // Check route params first, then query params
    return _routeParams[name] ?? _request.url.queryParameters[name];
  }

  @override
  Future<Map<String, String>> getParams() async {
    return {..._routeParams, ..._request.url.queryParameters};
  }

  @override
  Future<Map<String, String>> getQueryParams() async {
    return Map<String, String>.from(_request.url.queryParameters);
  }

  @override
  Future<Map<String, String>> getRouteParams() async {
    return Map<String, String>.from(_routeParams);
  }

  @override
  Future<Map<String, String>> getHeaders() async {
    return Map<String, String>.from(_request.headers);
  }

  @override
  Future<String?> getHeader(String name) async {
    return _request.headers[name.toLowerCase()];
  }

  @override
  Future<String> getBody() async {
    return await _request.readAsString();
  }

  @override
  Future<Map<String, dynamic>> getJsonBody() async {
    try {
      final body = await getBody();
      if (body.isEmpty) return {};

      return json.decode(body) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON in request body: $e');
    } catch (e) {
      throw FormatException('Invalid JSON in request body: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getFormData() async {
    if (_formData != null) return _formData!;

    final contentType = await getHeader('content-type') ?? '';
    _formData = {};

    if (contentType.startsWith('application/x-www-form-urlencoded')) {
      final body = await getBody();
      _formData = Uri.splitQueryString(body);
    } else if (contentType.startsWith('multipart/form-data')) {
      try {
        final form = _request.formData();
        if (form != null) {
          await for (final formData in form.formData) {
            final name = formData.name;
            final headers = formData.part.headers;

            if (headers.containsKey('content-disposition') &&
                headers['content-disposition']!.contains('filename=')) {
              // It's a file
              final filename = RegExp(
                r'filename="([^"]*)"',
              ).firstMatch(headers['content-disposition']!)?.group(1);
              final bytes = await formData.part.readBytes();

              if (!_formData!.containsKey(name)) {
                _formData![name] = [];
              }
              if (_formData![name] is! List) {
                _formData![name] = [_formData![name]];
              }

              (_formData![name] as List).add(
                _ShelfFormFile(
                  name: name,
                  filename: filename ?? '',
                  size: bytes.length,
                  contentType:
                      headers['content-type'] ?? 'application/octet-stream',
                  content: bytes,
                ),
              );
            } else {
              // It's a regular field
              final value = await formData.part.readString();
              if (!_formData!.containsKey(name)) {
                _formData![name] = value;
              } else if (_formData![name] is! List) {
                _formData![name] = [_formData![name], value];
              } else {
                (_formData![name] as List).add(value);
              }
            }
          }
        }
      } catch (e) {
        throw FormatException('Failed to parse multipart form data: $e');
      }
    } else if (contentType.startsWith('application/json')) {
      _formData = await getJsonBody();
    }

    return _formData!;
  }

  // === File Operations ===

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
    if (_uploadedFiles != null) return _uploadedFiles!;

    final contentType = await getHeader('content-type') ?? '';
    if (!contentType.startsWith('multipart/form-data')) {
      return _uploadedFiles = [];
    }

    final form = _request.formData();
    final files = <FormFile>[];
    if (form != null) {
      await for (final formData in form.formData) {
        final name = formData.name;
        final headers = formData.part.headers;
        if (headers.containsKey('content-disposition') &&
            headers['content-disposition']!.contains('filename=')) {
          final filename = RegExp(
            r'filename="([^"]*)"',
          ).firstMatch(headers['content-disposition']!)?.group(1);
          final bytes = await formData.part.readBytes();
          files.add(
            _ShelfFormFile(
              name: name,
              filename: filename ?? '',
              size: bytes.length,
              contentType:
                  headers['content-type'] ?? 'application/octet-stream',
              content: bytes,
            ),
          );
        }
      }
    }
    _uploadedFiles = files;
    return _uploadedFiles!;
  }

  @override
  Future<bool> hasFile(String fieldName) async {
    final files = await getUploadedFiles();
    return files.any((file) => file.name == fieldName);
  }

  // === Response Operations ===

  @override
  Future<void> setStatusCode(int code) async {
    _statusCode = code;
  }

  @override
  Future<void> setHeader(String name, String value) async {
    _headers[name.toLowerCase()] = value;
  }

  @override
  Future<void> write(String body) async {
    _body.add(body);
  }

  @override
  Future<void> writeJson(
    Map<String, dynamic> data, {
    int statusCode = 200,
  }) async {
    await setStatusCode(statusCode);
    _headers['content-type'] = 'application/json; charset=utf-8';
    await write(json.encode(data));
  }

  @override
  Future<void> redirect(String url, {int statusCode = 302}) async {
    await setStatusCode(statusCode);
    _headers['location'] = url;
    await write('');
  }

  // === Lifecycle ===

  @override
  Future<void> setup() async {
    // Any setup logic for Shelf adapter
  }

  @override
  Future<void> teardown() async {
    // Any cleanup logic for Shelf adapter
  }

  // === Shelf-specific methods ===

  /// Build the Shelf Response from the adapter state
  shelf.Response buildResponse() {
    final responseBody = _body.join('');
    final headers = <String, String>{};
    _headers.forEach((k, v) => headers[k.toLowerCase()] = v);

    // Ensure content type is set for JSON responses
    if (responseBody.isNotEmpty && headers['content-type'] == null) {
      try {
        json.decode(responseBody);
        headers['content-type'] = 'application/json; charset=utf-8';
      } catch (_) {
        // Not JSON, don't set content type
      }
    }

    return shelf.Response(_statusCode, body: responseBody, headers: headers);
  }

  /// Get the current response body content (for testing)
  String getResponseBody() {
    return _body.join('');
  }

  /// Create a ShelfAdapter from a Shelf Request with route parameters
  static ShelfAdapter fromRequest(
    shelf.Request request, [
    Map<String, String>? routeParams,
  ]) {
    return ShelfAdapter(request, routeParams ?? {});
  }
}

/// Implementation of FormFile for Shelf adapter
class _ShelfFormFile implements FormFile {
  @override
  String name;

  String filename;

  @override
  int size;

  @override
  String contentType;

  @override
  Uint8List content;

  _ShelfFormFile({
    required this.name,
    required this.filename,
    required this.size,
    required this.contentType,
    required this.content,
  });
}
