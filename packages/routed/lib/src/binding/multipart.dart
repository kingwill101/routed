import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:routed/src/binding/binding.dart';
import 'package:routed/src/binding/utils.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/validation/validator.dart';

/// Streams file data to disk, enforcing a maximum file size limit.
///
/// This function takes an HTTP request, a stream of file parts, a safe filename,
/// and a callback function to handle bytes read. It writes the file to a temporary
/// directory and ensures the file does not exceed the specified maximum file size.
///
/// Returns the file path if successful, or null if the file is rejected due to size constraints.
Future<String?> storeFileWithLimit({
  required HttpRequest request,
  required Stream<List<int>> part,
  required String safeFilename,
  required void Function(int chunkSize) onBytesRead,
  num maxFileSize = 20 * 1024 * 1024,
  num maxRequestSize = 5 * 1024 * 1024,
  Set<String> allowedFileExtensions = const {'jpg', 'png', 'txt'},
}) async {
  final tempDir = Directory.systemTemp;
  final uniqueId = DateTime.now().microsecondsSinceEpoch;
  final outPath = '${tempDir.path}/upload_${uniqueId}_$safeFilename';

  final outFile = File(outPath);
  final sink = outFile.openWrite();

  var fileBytesSoFar = 0;

  try {
    await for (final chunk in part) {
      fileBytesSoFar += chunk.length;
      onBytesRead(chunk.length);

      if (fileBytesSoFar > maxFileSize) {
        // File is too large
        await sink.close();
        await outFile.delete();
        _reject(
          request,
          'File exceeded max size of $maxFileSize bytes.',
          HttpStatus.requestEntityTooLarge,
        );
        return null;
      }

      sink.add(chunk);
    }
  } catch (e) {
    // On error, remove partial file
    await sink.close();
    if (await outFile.exists()) {
      await outFile.delete();
    }
    rethrow;
  } finally {
    await sink.close();
  }

  return outPath;
}

/// Sends an error response with the specified [code] and closes the request.
Future<void> _reject(HttpRequest request, String message,
    [int code = HttpStatus.badRequest]) async {
  if (!(await request.response.done)) {
    request.response
      ..statusCode = code
      ..write(message);
  }
  request.response.close();
}

/// Extracts a parameter (e.g., name="foo") from the content-disposition header.
String? extractParam(String headerLine, String param) {
  final match = RegExp('$param="([^"]*)"').firstMatch(headerLine);
  return match?.group(1);
}

/// Removes dangerous characters from a filename.
String sanitizeFilename(String filename) {
  return filename.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
}

/// Returns the lowercase extension of a filename without the dot.
String getExtension(String filename) {
  final idx = filename.lastIndexOf('.');
  if (idx == -1) return '';
  return filename.substring(idx + 1).toLowerCase();
}

/// Parses a multipart form from the given [EngineContext].
///
/// This function handles both file uploads and form fields, ensuring that the total
/// request size does not exceed the specified maximum memory limit.
Future<MultipartForm> parseMultipartForm(EngineContext context) async {
  final request = context.request;
  final contentType = request.headers.contentType;

  if (contentType == null ||
      contentType.primaryType != 'multipart' ||
      contentType.subType != 'form-data') {
    throw Exception('Not a multipart/form-data request');
  }

  final boundary = contentType.parameters['boundary'];
  if (boundary == null) {
    throw Exception('Missing boundary parameter');
  }

  // Use dynamic to allow storing String or List<String>
  final fields = <String, dynamic>{};
  final List<MultipartFile> files = [];
  int totalBytesRead = 0;

  try {
    await for (final part in MimeMultipartTransformer(boundary)
        .bind(context.request.httpRequest)) {
      final disposition = part.headers['content-disposition'] ?? '';
      final name = extractParam(disposition, 'name') ?? 'unnamed';
      final filename = extractParam(disposition, 'filename');

      if (filename != null) {
        // Handle file upload
        final safeFilename = sanitizeFilename(filename);
        final savedPath = await storeFileWithLimit(
          allowedFileExtensions:
              context.engineConfig.multipart.allowedExtensions,
          maxFileSize: context.engineConfig.multipart.maxFileSize,
          maxRequestSize: context.engineConfig.multipart.maxMemory,
          request: context.request.httpRequest,
          part: part,
          safeFilename: safeFilename,
          onBytesRead: (chunkSize) {
            totalBytesRead += chunkSize;
            if (totalBytesRead > context.engineConfig.multipart.maxMemory) {
              throw Exception(
                  'Request exceeded ${context.engineConfig.multipart.maxMemory} bytes');
            }
          },
        );

        if (savedPath != null) {
          if (files.where((MultipartFile file) => file.name == name).isEmpty) {
            files.add(MultipartFile(
              name: name,
              filename: filename,
              path: savedPath,
              size: await File(savedPath).length(),
              contentType:
                  part.headers['content-type'] ?? 'application/octet-stream',
            ));
          }
        }
      } else {
        // Handle form field
        final bytes = await part.fold<List<int>>(
          [],
          (prev, chunk) {
            totalBytesRead += chunk.length;
            if (totalBytesRead > context.engineConfig.multipart.maxMemory) {
              throw Exception(
                  'Request exceeded ${context.engineConfig.multipart.maxMemory} bytes');
            }
            return [...prev, ...chunk];
          },
        );

        final value = utf8.decode(bytes);

        if (!fields.containsKey(name)) {
          // If the field hasn't been seen yet, store as a String
          fields[name] = value;
        } else {
          // If the field exists, then ensure it is a List and append
          final existing = fields[name];
          if (existing is String) {
            fields[name] = [existing, value];
          } else if (existing is List) {
            existing.add(value);
          }
        }
      }
    }
  } catch (e) {
    throw Exception(e);
  }

  return MultipartForm(
    fields: fields,
    files: files,
  );
}

/// Represents a file in a multipart form.
class MultipartFile {
  final String filename;
  final String path;
  final int size;
  final String contentType;
  final String name;

  MultipartFile({
    required this.name,
    required this.filename,
    required this.path,
    required this.size,
    required this.contentType,
  });
}

/// Represents a parsed multipart form with fields and files.
class MultipartForm {
  final Map<String, dynamic> fields;
  final List<MultipartFile> files;

  MultipartForm({
    this.fields = const {},
    this.files = const [],
  });
}

/// Parses a URL-encoded form from the given [EngineContext].
///
/// This function reads the request body, decodes it, and parses the form-encoded data.
Future<Map<String, dynamic>> parseForm(EngineContext ctx) async {
  final bodyBytes = await ctx.request.bytes;
  final bodyString = utf8.decode(bodyBytes);
  // Parse form-encoded data, e.g., "key=val&foo=bar"
  return parseUrlEncoded(bodyString);
}

/// A binding for handling multipart form data.
class MultipartBinding extends Binding {
  @override
  String get name => 'multipart';

  @override
  Future<void> bind(
    EngineContext context,
    dynamic instance, {
    Map<String, String>? rules,
  }) async {
    final multipartForm = await context.multipartForm;
    final data = multipartForm.fields;

    if (instance is Map) {
      for (final entry in data.entries) {
        if (entry.value is MultipartFile) continue;
        instance[entry.key] = entry.value;
      }
    }
  }

  @override
  Future<void> validate(
      EngineContext context,
      // ignore: avoid_renaming_method_parameters
      Map<String, String> rules,
      {bool bail = false}) async {
    final multipartForm = await context.multipartForm;
    final data = multipartForm.fields;

    final validator = Validator.make(rules, bail: bail);

    for (final file in multipartForm.files) {
      data[file.name] = file;
    }
    final errors = validator.validate(data);

    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
  }
}
