import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:file/file.dart' as fs;
import 'package:file/local.dart' as local_fs;
import 'package:mime/mime.dart';
import 'package:routed/src/binding/binding.dart';
import 'package:routed/src/binding/utils.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/validation/validator.dart';

/// Streams file data to disk, enforcing a maximum file size limit.
///
/// This function takes a stream of file parts, a safe filename,
/// and a callback function to handle bytes read. It writes the file to a temporary
/// directory and ensures the file does not exceed the specified maximum file size.
///
/// Returns the file path if successful.
/// Throws [FileTooLargeException] if the file exceeds the maximum size.
Future<String> storeFileWithLimit({
  required Stream<List<int>> part,
  required String safeFilename,
  required void Function(int chunkSize) onBytesRead,
  required fs.FileSystem fileSystem,
  num maxFileSize = 20 * 1024 * 1024,
  Set<String> allowedFileExtensions = const {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'pdf',
  },
  String? uploadDirectory,
  int? filePermissions,
  UploadQuotaTracker? quota,
}) async {
  final normalizedAllowedExtensions = allowedFileExtensions
      .map((ext) => ext.toLowerCase())
      .toSet();
  final extension = getExtension(safeFilename);
  final extensionsConfigured = normalizedAllowedExtensions.isNotEmpty;
  if (!extensionsConfigured || extension.isEmpty) {
    throw FileExtensionNotAllowedException(
      extension,
      normalizedAllowedExtensions,
    );
  }
  if (!normalizedAllowedExtensions.contains(extension)) {
    throw FileExtensionNotAllowedException(
      extension,
      normalizedAllowedExtensions,
    );
  }

  final fs.Directory baseDir =
      uploadDirectory == null || uploadDirectory.isEmpty
      ? fileSystem.systemTempDirectory
      : fileSystem.directory(uploadDirectory);
  if (!await baseDir.exists()) {
    await baseDir.create(recursive: true);
  }
  if (filePermissions != null) {
    await _applyPermissions(fileSystem, baseDir, filePermissions);
  }

  final uniqueId = DateTime.now().microsecondsSinceEpoch;
  final fs.File outFile = baseDir.childFile('upload_${uniqueId}_$safeFilename');
  final outPath = outFile.path;
  final sink = outFile.openWrite();

  var fileBytesSoFar = 0;
  var sinkClosed = false;

  try {
    await for (final chunk in part) {
      final chunkSize = chunk.length;
      onBytesRead(chunkSize);

      if (quota != null && !quota.tryConsume(chunkSize)) {
        throw FileQuotaExceededException(quota.maxDiskUsage);
      }

      fileBytesSoFar += chunkSize;

      if (fileBytesSoFar > maxFileSize) {
        throw FileTooLargeException(
          'File exceeded max size of $maxFileSize bytes.',
          maxFileSize,
        );
      }

      sink.add(chunk);
    }
  } catch (e) {
    if (!sinkClosed) {
      await sink.close();
      sinkClosed = true;
    }
    if (fileBytesSoFar > 0) {
      quota?.release(fileBytesSoFar);
      fileBytesSoFar = 0;
    }
    if (await outFile.exists()) {
      await outFile.delete();
    }
    rethrow;
  } finally {
    if (!sinkClosed) {
      await sink.close();
      sinkClosed = true;
    }
  }

  if (filePermissions != null && await outFile.exists()) {
    await _applyPermissions(fileSystem, outFile, filePermissions);
  }

  return outPath;
}

Future<void> _applyPermissions(
  fs.FileSystem fileSystem,
  fs.FileSystemEntity entity,
  int mode,
) async {
  if (fileSystem is! local_fs.LocalFileSystem) {
    return;
  }
  if (!Platform.isWindows && !Platform.isIOS) {
    final octal = mode.toRadixString(8);
    try {
      final result = await Process.run('chmod', [octal, entity.path]);
      if (result.exitCode != 0) {
        // ignore: avoid_print
        print(
          'Failed to apply permissions $octal to ${entity.path}: ${result.stderr}',
        );
      }
    } catch (_) {
      // ignore inability to set permissions.
    }
  }
}

/// Exception thrown when a file upload exceeds the maximum allowed size.
class FileTooLargeException implements Exception {
  final String message;
  final num maxSize;

  FileTooLargeException(this.message, this.maxSize);

  @override
  String toString() => 'FileTooLargeException: $message';
}

/// Exception thrown when a file upload has a disallowed extension.
class FileExtensionNotAllowedException implements Exception {
  FileExtensionNotAllowedException(this.extension, this.allowedExtensions);

  final String extension;
  final Set<String> allowedExtensions;

  @override
  String toString() {
    if (allowedExtensions.isEmpty) {
      return 'FileExtensionNotAllowedException: No upload extensions are currently allowed.';
    }
    return 'FileExtensionNotAllowedException: Extension "$extension" is not allowed. Allowed extensions: ${allowedExtensions.join(', ')}';
  }
}

/// Exception thrown when total disk usage for a request exceeds the configured limit.
class FileQuotaExceededException implements Exception {
  FileQuotaExceededException(this.maxDiskUsage);

  final int maxDiskUsage;

  @override
  String toString() => maxDiskUsage <= 0
      ? 'FileQuotaExceededException: Upload quota exceeded.'
      : 'FileQuotaExceededException: Upload quota exceeded $maxDiskUsage bytes.';
}

class UploadQuotaTracker {
  UploadQuotaTracker(this.maxDiskUsage);

  final int maxDiskUsage;
  int _used = 0;

  bool get _enabled => maxDiskUsage > 0;

  bool tryConsume(int bytes) {
    if (!_enabled) return true;
    if (_used + bytes > maxDiskUsage) {
      return false;
    }
    _used += bytes;
    return true;
  }

  void release(int bytes) {
    if (!_enabled) return;
    _used -= bytes;
    if (_used < 0) {
      _used = 0;
    }
  }

  void reset() {
    _used = 0;
  }
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
  final fileSystem = context.engineConfig.fileSystem;

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
  final quota = UploadQuotaTracker(context.engineConfig.multipart.maxDiskUsage);
  final createdFiles = <String>[];
  var parsingCompleted = false;

  try {
    await for (final part in MimeMultipartTransformer(
      boundary,
    ).bind(context.request.stream)) {
      final disposition = part.headers['content-disposition'] ?? '';
      final name = extractParam(disposition, 'name') ?? 'unnamed';
      final filename = extractParam(disposition, 'filename');

      if (filename != null) {
        // Handle file upload
        final safeFilename = sanitizeFilename(filename);
        try {
          final savedPath = await storeFileWithLimit(
            allowedFileExtensions:
                context.engineConfig.multipart.allowedExtensions,
            maxFileSize: context.engineConfig.multipart.maxFileSize,
            uploadDirectory: context.engineConfig.multipart.uploadDirectory,
            filePermissions: context.engineConfig.multipart.filePermissions,
            quota: quota,
            part: part,
            safeFilename: safeFilename,
            fileSystem: fileSystem,
            onBytesRead: (chunkSize) {
              totalBytesRead += chunkSize;
              if (totalBytesRead > context.engineConfig.multipart.maxMemory) {
                throw Exception(
                  'Request exceeded ${context.engineConfig.multipart.maxMemory} bytes',
                );
              }
            },
          );

          createdFiles.add(savedPath);

          if (files.where((MultipartFile file) => file.name == name).isEmpty) {
            final savedFile = fileSystem.file(savedPath);
            files.add(
              MultipartFile(
                name: name,
                filename: filename,
                path: savedPath,
                size: await savedFile.length(),
                contentType:
                    part.headers['content-type'] ?? 'application/octet-stream',
              ),
            );
          }
        } on FileTooLargeException catch (_) {
          // File exceeded max size - skip this file but continue processing
          // The exception message contains details about the size limit
          continue;
        }
      } else {
        // Handle form field
        final bytes = await part.fold<List<int>>([], (prev, chunk) {
          totalBytesRead += chunk.length;
          if (totalBytesRead > context.engineConfig.multipart.maxMemory) {
            throw Exception(
              'Request exceeded ${context.engineConfig.multipart.maxMemory} bytes',
            );
          }
          return [...prev, ...chunk];
        });

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
    parsingCompleted = true;
  } finally {
    if (!parsingCompleted) {
      for (final path in createdFiles.reversed) {
        try {
          final file = fileSystem.file(path);
          if (await file.exists()) {
            quota.release(await file.length());
            await file.delete();
          }
        } catch (_) {}
      }
      quota.reset();
    }
  }

  return MultipartForm(fields: fields, files: files);
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

  MultipartForm({this.fields = const {}, this.files = const []});
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
  MimeType get mimeType => MimeType.multipartPostForm;

  @override
  Future<T> bind<T>(
    EngineContext context,
    T instance, {
    Map<String, String>? rules,
  }) async {
    final multipartForm = await context.multipartForm;
    final data = multipartForm.fields;

    if (instance is Map) {
      for (final entry in data.entries) {
        if (entry.value is MultipartFile) continue;
        instance[entry.key] = entry.value;
      }
    } else if (instance is Bindable) {
      instance.bind(data);
    }
    return instance;
  }

  @override
  Future<void> validate(
    EngineContext context,
    // ignore: avoid_renaming_method_parameters
    Map<String, String> rules, {
    bool bail = false,
    Map<String, String>? messages,
  }) async {
    final multipartForm = await context.multipartForm;
    final data = multipartForm.fields;

    final registry = requireValidationRegistry(context.container);
    final validator = Validator.make(
      rules,
      registry: registry,
      bail: bail,
      messages: messages,
    );

    for (final file in multipartForm.files) {
      data[file.name] = file;
    }
    final errors = validator.validate(data);

    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
  }
}
