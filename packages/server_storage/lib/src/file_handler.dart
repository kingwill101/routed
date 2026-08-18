import 'dart:async';
import 'dart:io';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:mime/mime.dart';

import 'static_file_sink.dart';

/// Represents a directory in the file system.
///
/// The [Dir] class provides a way to interact with a directory in the file system.
/// It allows you to specify the path to the directory, whether to list the contents
/// of the directory, and which file system to use.
class Dir {
  /// The path to the directory.
  final String path;

  /// Whether to list the contents of the directory.
  final bool listDirectory;

  /// File served when a request targets a directory.
  final String indexFile;

  /// The file system to use.
  final file.FileSystem fileSystem;

  /// Creates a [Dir] instance.
  ///
  /// The [path] parameter specifies the path to the directory.
  /// The [listDirectory] parameter specifies whether to list the contents of the directory.
  /// The [fileSystem] parameter specifies the file system to use.
  Dir(
    this.path, {
    this.listDirectory = false,
    this.indexFile = 'index.html',
    file.FileSystem? fileSystem,
  }) : fileSystem = fileSystem ?? const local.LocalFileSystem();
}

/// Handles file operations such as serving files and directories over HTTP.
///
/// Portable: depends only on [StaticFileSink], not on any framework.
class FileHandler {
  /// The root path from which files are served.
  final String rootPath;

  /// The file system to use.
  final file.FileSystem fileSystem;

  /// Whether directory listing is allowed.
  final bool allowDirectoryListing;

  /// File served when a request targets a directory.
  final String indexFile;

  /// Private constructor that takes normalized path.
  const FileHandler._({
    required this.rootPath,
    required this.fileSystem,
    required this.allowDirectoryListing,
    required this.indexFile,
  });

  /// Factory constructor that handles path normalization.
  ///
  /// The [rootPath] parameter specifies the root path from which files are served.
  /// The [fileSystem] parameter specifies the file system to use.
  /// The [allowDirectoryListing] parameter specifies whether directory listing is allowed.
  factory FileHandler({
    required String rootPath,
    file.FileSystem fileSystem = const local.LocalFileSystem(),
    bool allowDirectoryListing = false,
    String indexFile = 'index.html',
  }) {
    final pathContext = fileSystem.path;
    final currentDir = pathContext.normalize(fileSystem.currentDirectory.path);
    final normalizedPath = pathContext.normalize(
      pathContext.isAbsolute(rootPath)
          ? rootPath
          : pathContext.join(currentDir, rootPath),
    );

    return FileHandler._(
      rootPath: normalizedPath,
      fileSystem: fileSystem,
      allowDirectoryListing: allowDirectoryListing,
      indexFile: indexFile,
    );
  }

  /// Factory constructor that creates a [FileHandler] from a [Dir] instance.
  ///
  /// The [dir] parameter specifies the directory from which files are served.
  factory FileHandler.fromDir(Dir dir) {
    final pathContext = dir.fileSystem.path;
    final currentDir = pathContext.normalize(
      dir.fileSystem.currentDirectory.path,
    );
    final normalizedPath = pathContext.normalize(
      pathContext.isAbsolute(dir.path)
          ? dir.path
          : pathContext.join(currentDir, dir.path),
    );

    return FileHandler._(
      rootPath: normalizedPath,
      fileSystem: dir.fileSystem,
      allowDirectoryListing: dir.listDirectory,
      indexFile: dir.indexFile,
    );
  }

  /// Serves a file over HTTP via [sink].
  ///
  /// The [file] parameter specifies the relative file path under [rootPath].
  Future<void> serveFile(StaticFileSink sink, String file) async {
    try {
      final pathContext = fileSystem.path;
      final filePath = pathContext.normalize(pathContext.join(rootPath, file));

      // Robust security check to prevent directory traversal
      if (rootPath != filePath && !pathContext.isWithin(rootPath, filePath)) {
        sink.abortWithStatus(
          HttpStatus.forbidden,
          sink.method == 'HEAD' ? '' : 'Access denied',
        );
        return;
      }

      final fileStat = await fileSystem.stat(filePath);

      if (fileStat.type == FileSystemEntityType.directory) {
        await serveDirectory(sink, filePath, file);
      } else if (fileStat.type == FileSystemEntityType.file) {
        await _serveFile(sink, filePath, fileStat);
      } else {
        sink.abortWithStatus(
          HttpStatus.notFound,
          sink.method == 'HEAD' ? '' : 'Not Found',
        );
      }
    } catch (e) {
      sink.abortWithStatus(
        HttpStatus.internalServerError,
        'Internal Server Error',
      );
    }
  }

  /// Serves a directory over HTTP.
  Future<void> serveDirectory(
    StaticFileSink sink,
    String dirPath, [
    String parent = '',
  ]) async {
    final pathContext = fileSystem.path;
    final baseDir = pathContext.isAbsolute(dirPath)
        ? dirPath
        : pathContext.join(rootPath, dirPath);
    // First try to serve the configured index file if it exists.
    final indexPath = indexFile.isEmpty
        ? null
        : pathContext.join(baseDir, indexFile);

    try {
      if (indexPath != null) {
        final indexFileStat = await fileSystem.stat(indexPath);
        if (indexFileStat.type == FileSystemEntityType.file) {
          await _serveFile(sink, indexPath, indexFileStat);
          return;
        }
      }
    } catch (_) {
      // No index file, continue to directory listing check.
    }

    // Check if directory listing is allowed
    if (!allowDirectoryListing) {
      sink.abortWithStatus(
        HttpStatus.notFound,
        sink.method == 'HEAD' ? '' : 'Not Found',
      );
      return;
    }

    await _listDirectory(sink, dirPath, parent);
  }

  Future<void> _listDirectory(
    StaticFileSink sink,
    String dirPath, [
    String? parent,
  ]) async {
    final pathContext = fileSystem.path;
    final directory = fileSystem.directory(pathContext.join(rootPath, dirPath));
    final entities = await directory.list().toList();

    // Directory listing should explicitly send text/html with utf-8 charset
    sink.setHeader(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
    sink.write('<!DOCTYPE html><html><body><ul>');

    for (var entity in entities) {
      final name = pathContext.basename(entity.path);
      final stat = await entity.stat();
      final isDir = stat.type == file.FileSystemEntityType.directory;
      final displayName = isDir ? '${entity.parent.basename}/$name/' : name;
      final prefix = (parent != null && parent.isNotEmpty) ? '$parent/' : '';
      final encodedName = Uri.encodeComponent("$prefix$name");
      sink.write('<li><a href="$encodedName">$displayName</a></li>');
    }

    sink.write('</ul></body></html>');
    await sink.close();
  }

  Future<void> _serveFile(
    StaticFileSink sink,
    String filePath,
    FileStat fileStat,
  ) async {
    final file = fileSystem.file(filePath);

    // Conditional request handling
    if (_handleIfModifiedSince(sink, fileStat.modified)) {
      return;
    }

    final length = fileStat.size;
    final contentType = _getContentType(file.path);

    sink.setHeader(HttpHeaders.contentTypeHeader, contentType.toString());

    sink.setHeader(HttpHeaders.contentLengthHeader, length.toString());
    sink.setHeader(
      HttpHeaders.lastModifiedHeader,
      HttpDate.format(fileStat.modified),
    );

    // Range request support
    final range = sink.headers.value(HttpHeaders.rangeHeader);
    final isHead = sink.method == 'HEAD';
    if (isHead) {
      sink.abort();
      return;
    }

    if (range != null) {
      await _handleRangeRequest(sink, file, length, range);
    } else {
      await sink.addStream(file.openRead());
      await sink.close();
    }
  }

  bool _handleIfModifiedSince(StaticFileSink sink, DateTime lastModified) {
    final ifModifiedSince = sink.headers.ifModifiedSince;
    if (ifModifiedSince != null) {
      final lastModifiedTruncated =
          lastModified.toUtc().millisecondsSinceEpoch ~/ 1000;
      final imsTruncated =
          ifModifiedSince.toUtc().millisecondsSinceEpoch ~/ 1000;
      if (lastModifiedTruncated <= imsTruncated) {
        sink.statusCode = HttpStatus.notModified;
        unawaited(sink.close());
        return true;
      }
    }
    return false;
  }

  Future<void> _handleRangeRequest(
    StaticFileSink sink,
    File file,
    int fileLength,
    String rangeHeader,
  ) async {
    final ranges = _parseRangeHeader(rangeHeader, fileLength);
    if (ranges == null || ranges.isEmpty) {
      sink.setHeader(HttpHeaders.contentRangeHeader, 'bytes */$fileLength');
      sink.abortWithStatus(
        HttpStatus.requestedRangeNotSatisfiable,
        'Requested Range Not Satisfiable',
      );
      return;
    }

    if (ranges.length == 1) {
      final range = ranges[0];
      sink.statusCode = HttpStatus.partialContent;
      sink.setHeader(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$fileLength',
      );
      sink.setHeader(
        HttpHeaders.contentLengthHeader,
        (range.end - range.start + 1).toString(),
      );

      await sink.addStream(file.openRead(range.start, range.end + 1));
      await sink.close();
    } else {
      sink.abortWithStatus(
        HttpStatus.notImplemented,
        'Multiple Ranges Not Supported',
      );
    }
  }

  List<_ByteRange>? _parseRangeHeader(String header, int fileLength) {
    const prefix = 'bytes=';
    if (!header.startsWith(prefix)) {
      return null;
    }
    final rangeStrings = header.substring(prefix.length).split(',');
    final ranges = <_ByteRange>[];

    for (var rangeStr in rangeStrings) {
      final range = _parseSingleRange(rangeStr.trim(), fileLength);
      if (range != null) {
        ranges.add(range);
      }
    }
    return ranges;
  }

  _ByteRange? _parseSingleRange(String rangeStr, int fileLength) {
    final parts = rangeStr.split('-');
    if (parts.length != 2) return null;

    int? start;
    int? end;

    if (parts[0].isNotEmpty) {
      start = int.tryParse(parts[0]);
      if (start == null || start >= fileLength) return null;
    }

    if (parts[1].isNotEmpty) {
      end = int.tryParse(parts[1]);
      if (end == null) return null;
    }

    if (start != null && end != null) {
      if (end < start) return null;
    }

    if (start == null) {
      // Suffix byte range: "-<length>"
      start = fileLength - end!;
      end = fileLength - 1;
    } else if (end == null || end >= fileLength) {
      end = fileLength - 1;
    }

    return _ByteRange(start, end);
  }

  ContentType _getContentType(String filePath) {
    final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
    return ContentType.parse(mimeType);
  }
}

/// Represents a byte range for partial content delivery.
class _ByteRange {
  /// The start byte of the range.
  final int start;

  /// The end byte of the range.
  final int end;

  /// Creates a [_ByteRange] instance.
  _ByteRange(this.start, this.end);
}
