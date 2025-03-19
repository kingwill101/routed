import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';

/// A builder for multipart requests.
/// This class helps in constructing multipart/form-data requests by allowing
/// the addition of form fields and files. It then builds the request body
/// as a stream of bytes.
class MultipartRequestBuilder {
  /// List of form fields to be included in the multipart request.
  final List<MultipartField> fields = [];

  /// List of files to be included in the multipart request.
  final List<MultipartFile> files = [];

  /// Boundary string used to separate parts in the multipart request.
  String? _boundary;

  /// Flag indicating whether the body has been processed.
  bool _isBodyProcessed = false;

  /// Stream of bytes representing the body of the multipart request.
  Stream<List<int>>? _bodyStream;

  /// Adds a form field to the multipart request.
  ///
  /// [name] is the name of the form field.
  /// [value] is the value of the form field.
  void addField(String name, String value) {
    _assertNotProcessed();
    fields.add(MultipartField(name, value));
  }

  /// Adds a file to the multipart request from bytes.
  ///
  /// [name] is the name of the file field.
  /// [bytes] is the content of the file as bytes.
  /// [filename] is the name of the file (optional).
  /// [contentType] is the MIME type of the file (optional).
  void addFileFromBytes({
    required String name,
    required Uint8List bytes,
    String? filename,
    MediaType? contentType,
  }) {
    _assertNotProcessed();
    files.add(MultipartFile.fromBytes(
      name: name,
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    ));
  }

  /// Adds a file to the multipart request from a string.
  ///
  /// [name] is the name of the file field.
  /// [content] is the content of the file as a string.
  /// [filename] is the name of the file (optional).
  /// [contentType] is the MIME type of the file (optional).
  void addFileFromString({
    required String name,
    required String content,
    String? filename,
    MediaType? contentType,
  }) {
    _assertNotProcessed();
    files.add(MultipartFile.fromString(
      name: name,
      content: content,
      filename: filename,
      contentType: contentType,
    ));
  }

  /// Adds a file to the multipart request from a file path.
  ///
  /// [name] is the name of the file field.
  /// [filePath] is the path to the file.
  /// [filename] is the name of the file (optional).
  /// [contentType] is the MIME type of the file (optional).
  Future<void> addFileFromPath({
    required String name,
    required String filePath,
    String? filename,
    MediaType? contentType,
  }) async {
    _assertNotProcessed();
    final file = await MultipartFile.fromPath(
      name: name,
      filePath: filePath,
      filename: filename,
      contentType: contentType,
    );
    files.add(file);
  }

  /// Builds the multipart request and returns the body as a stream of bytes.
  ///
  /// This method constructs the multipart request body by iterating over
  /// the added fields and files, and encoding them into the appropriate
  /// format. It then returns the body as a stream of bytes.
  Stream<List<int>> buildBody() {
    if (_isBodyProcessed) {
      throw StateError('The body has already been processed.');
    }

    _boundary = 'boundary${DateTime.now().millisecondsSinceEpoch}';
    final bodyStream = StreamController<List<int>>();

    void write(String text) {
      bodyStream.add(utf8.encode(text));
    }

    void writeLine(String text) {
      write('$text\r\n');
    }

    for (final field in fields) {
      writeLine('--$_boundary');
      writeLine('Content-Disposition: form-data; name="${field.name}"');
      writeLine('');
      writeLine(field.value);
    }

    for (final file in files) {
      writeLine('--$_boundary');
      writeLine(
        'Content-Disposition: form-data; name="${file.name}"; filename="${file.filename}"',
      );
      if (file.contentType != null) {
        writeLine('Content-Type: ${file.contentType}');
      }
      writeLine('');
      bodyStream.add(file.bytes);
      writeLine('');
    }

    writeLine('--$_boundary--');
    bodyStream.close();

    _isBodyProcessed = true;
    _bodyStream = bodyStream.stream;

    return _bodyStream!;
  }

  /// Returns the headers for the multipart request.
  ///
  /// This method returns a map containing the headers required for the
  /// multipart request, including the Content-Type header with the boundary.
  Map<String, String> getHeaders() {
    if (!_isBodyProcessed) {
      throw StateError('The body must be processed before accessing headers.');
    }
    return {
      'Content-Type': 'multipart/form-data; boundary=$_boundary',
    };
  }

  /// Returns the boundary used for the multipart request.
  ///
  /// This method returns the boundary string used to separate parts in the
  /// multipart request. The boundary is generated when the body is built.
  String? getBoundary() {
    if (!_isBodyProcessed) {
      throw StateError(
          'The body must be processed before accessing the boundary.');
    }
    return _boundary;
  }

  /// Asserts that the body has not been processed yet.
  ///
  /// This method throws a StateError if the body has already been processed,
  /// ensuring that no further modifications are allowed.
  void _assertNotProcessed() {
    if (_isBodyProcessed) {
      throw StateError(
          'The body has already been processed. No further modifications are allowed.');
    }
  }
}

/// Represents a form field in a multipart request.
///
/// This class holds the name and value of a form field to be included
/// in the multipart request.
class MultipartField {
  /// The name of the form field.
  final String name;

  /// The value of the form field.
  final String value;

  /// Creates a MultipartField with the given [name] and [value].
  MultipartField(this.name, this.value);
}

/// Represents a file in a multipart request.
///
/// This class holds the name, content, filename, and content type of a file
/// to be included in the multipart request.
class MultipartFile {
  /// The name of the file field.
  final String name;

  /// The content of the file as bytes.
  final Uint8List bytes;

  /// The name of the file (optional).
  final String? filename;

  /// The MIME type of the file (optional).
  final MediaType? contentType;

  MultipartFile._({
    required this.name,
    required this.bytes,
    this.filename,
    this.contentType,
  });

  /// Creates a MultipartFile from raw bytes.
  ///
  /// [name] is the name of the file field.
  /// [bytes] is the content of the file as bytes.
  /// [filename] is the name of the file (optional).
  /// [contentType] is the MIME type of the file (optional).
  factory MultipartFile.fromBytes({
    required String name,
    required Uint8List bytes,
    String? filename,
    MediaType? contentType,
  }) {
    return MultipartFile._(
      name: name,
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    );
  }

  /// Creates a MultipartFile from a string.
  ///
  /// [name] is the name of the file field.
  /// [content] is the content of the file as a string.
  /// [filename] is the name of the file (optional).
  /// [contentType] is the MIME type of the file (optional).
  factory MultipartFile.fromString({
    required String name,
    required String content,
    String? filename,
    MediaType? contentType,
  }) {
    return MultipartFile._(
      name: name,
      bytes: utf8.encode(content),
      filename: filename,
      contentType: contentType,
    );
  }

  /// Creates a MultipartFile from a file path.
  ///
  /// [name] is the name of the file field.
  /// [filePath] is the path to the file.
  /// [filename] is the name of the file (optional).
  /// [contentType] is the MIME type of the file (optional).
  static Future<MultipartFile> fromPath({
    required String name,
    required String filePath,
    String? filename,
    MediaType? contentType,
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return MultipartFile._(
      name: name,
      bytes: bytes,
      filename: filename ?? file.path,
      contentType: contentType,
    );
  }
}
