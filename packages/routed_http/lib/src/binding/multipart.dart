// Uploads use asynchronous filesystem APIs so request handling does not block.
// ignore_for_file: avoid_slow_async_io
import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:file/file.dart' as fs;
import 'package:file/local.dart' as local_fs;
import 'package:mime/mime.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_http/src/binding/binding.dart';
import 'package:routed_http/src/binding/utils.dart';
import 'package:routed_http/src/context/form_cache.dart';

/// Stores a multipart file while enforcing extension, size, and quota limits.
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
  final baseDir = uploadDirectory == null || uploadDirectory.isEmpty
      ? fileSystem.systemTempDirectory
      : fileSystem.directory(uploadDirectory);
  if (!await baseDir.exists()) {
    await baseDir.create(recursive: true);
  }
  if (filePermissions != null) {
    await _applyPermissions(fileSystem, baseDir, filePermissions);
  }
  final uniqueId = DateTime.now().microsecondsSinceEpoch;
  final outFile = baseDir.childFile('upload_${uniqueId}_$safeFilename');
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
  } on Object catch (_) {
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
        // This diagnostic is retained because the helper has no logger
        // dependency and this path is only an operational warning.
        // ignore: avoid_print
        print(
          'Failed to apply permissions $octal to ${entity.path}: '
          '${result.stderr}',
        );
      }
    } on Object catch (_) {}
  }
}

/// Reports that an uploaded file exceeded the configured size limit.
class FileTooLargeException implements Exception {
  /// Creates an exception with a human-readable [message] and [maxSize].
  FileTooLargeException(this.message, this.maxSize);

  /// The explanation of why the upload was rejected.
  final String message;

  /// The maximum permitted file size in bytes.
  final num maxSize;
  @override
  String toString() => 'FileTooLargeException: $message';
}

/// Reports that an uploaded file has a disallowed extension.
class FileExtensionNotAllowedException implements Exception {
  /// Creates an exception for [extension] and the configured allow-list.
  FileExtensionNotAllowedException(this.extension, this.allowedExtensions);

  /// The extension found on the uploaded filename.
  final String extension;

  /// The normalized extensions accepted by the upload policy.
  final Set<String> allowedExtensions;
  @override
  String toString() {
    if (allowedExtensions.isEmpty) {
      return 'FileExtensionNotAllowedException: No upload extensions are '
          'currently allowed.';
    }
    return 'FileExtensionNotAllowedException: Extension "$extension" is not '
        'allowed. Allowed extensions: '
        '${allowedExtensions.join(', ')}';
  }
}

/// Reports that the upload quota would be exceeded.
class FileQuotaExceededException implements Exception {
  /// Creates an exception for a quota of [maxDiskUsage] bytes.
  FileQuotaExceededException(this.maxDiskUsage);

  /// The configured maximum number of bytes, or a non-positive value when
  /// the quota is not bounded.
  final int maxDiskUsage;
  @override
  String toString() => maxDiskUsage <= 0
      ? 'FileQuotaExceededException: Upload quota exceeded.'
      : 'FileQuotaExceededException: Upload quota exceeded '
            '$maxDiskUsage bytes.';
}

/// Tracks bytes consumed by uploads sharing a quota.
class UploadQuotaTracker {
  /// Creates a tracker with a maximum usage of [maxDiskUsage] bytes.
  UploadQuotaTracker(this.maxDiskUsage);

  /// The maximum number of bytes that may be consumed.
  final int maxDiskUsage;
  int _used = 0;
  bool get _enabled => maxDiskUsage > 0;

  /// Attempts to reserve [bytes] and returns whether the reservation fits.
  bool tryConsume(int bytes) {
    if (!_enabled) return true;
    if (_used + bytes > maxDiskUsage) {
      return false;
    }
    _used += bytes;
    return true;
  }

  /// Releases a previous reservation of [bytes].
  void release(int bytes) {
    if (!_enabled) return;
    _used -= bytes;
    if (_used < 0) {
      _used = 0;
    }
  }

  /// Clears all reservations made by this tracker.
  void reset() {
    _used = 0;
  }
}

/// Extracts a quoted parameter from a multipart header line.
String? extractParam(String headerLine, String param) {
  final match = RegExp('$param="([^"]*)"').firstMatch(headerLine);
  return match?.group(1);
}

/// Replaces filename characters that are unsafe for a local path.
String sanitizeFilename(String filename) {
  return filename.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
}

/// Returns the lower-case extension from [filename], or an empty string.
String getExtension(String filename) {
  final idx = filename.lastIndexOf('.');
  if (idx == -1) return '';
  return filename.substring(idx + 1).toLowerCase();
}

/// Parses multipart fields and stores uploaded files using engine settings.
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
  final fields = <String, dynamic>{};
  final files = <MultipartFile>[];
  var totalBytesRead = 0;
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
                final maxMemory = context.engineConfig.multipart.maxMemory;
                throw Exception('Request exceeded $maxMemory bytes');
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
          continue;
        }
      } else {
        final bytes = await part.fold<List<int>>([], (prev, chunk) {
          totalBytesRead += chunk.length;
          if (totalBytesRead > context.engineConfig.multipart.maxMemory) {
            final maxMemory = context.engineConfig.multipart.maxMemory;
            throw Exception('Request exceeded $maxMemory bytes');
          }
          return [...prev, ...chunk];
        });
        final value = utf8.decode(bytes);
        if (!fields.containsKey(name)) {
          fields[name] = value;
        } else {
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
        } on Object catch (_) {}
      }
      quota.reset();
    }
  }
  return MultipartForm(fields: fields, files: files);
}

/// Describes a multipart file stored during request parsing.
class MultipartFile {
  /// Creates a stored file description.
  MultipartFile({
    required this.name,
    required this.filename,
    required this.path,
    required this.size,
    required this.contentType,
  });

  /// The original filename supplied by the client.
  final String filename;

  /// The path where the file was stored.
  final String path;

  /// The stored file size in bytes.
  final int size;

  /// The detected or supplied content type.
  final String contentType;

  /// The multipart field name containing the file.
  final String name;
}

/// The fields and files parsed from a multipart request.
class MultipartForm {
  /// Creates a multipart result with optional [fields] and [files].
  MultipartForm({this.fields = const {}, this.files = const []});

  /// Form fields keyed by their multipart field name.
  final Map<String, dynamic> fields;

  /// Files stored while parsing the request.
  final List<MultipartFile> files;
}

/// Parses a URL-encoded request body into a form map.
Future<Map<String, dynamic>> parseForm(EngineContext ctx) async {
  final bodyBytes = await ctx.request.bytes;
  final bodyString = utf8.decode(bodyBytes);
  return parseUrlEncoded(bodyString);
}

/// Binds multipart form fields to maps or [Bindable] models.
class MultipartBinding extends Binding {
  @override
  String get name => 'multipart';
  @override
  MimeType get mimeType => MimeType.multipartPostForm;
  @override
  /// Binds multipart fields to [instance].
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
      (instance as Bindable).bind(data);
    }
    return instance;
  }
}
