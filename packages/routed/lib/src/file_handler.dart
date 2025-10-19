import 'dart:async';
import 'dart:io';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:routed/src/context/context.dart';

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

  /// The file system to use.
  final file.FileSystem fileSystem;

  /// Creates a [Dir] instance.
  ///
  /// The [path] parameter specifies the path to the directory.
  /// The [listDirectory] parameter specifies whether to list the contents of the directory.
  /// The [fileSystem] parameter specifies the file system to use.
  Dir(this.path, {this.listDirectory = false, file.FileSystem? fileSystem})
    : fileSystem = fileSystem ?? const local.LocalFileSystem();
}

/// Handles file operations such as serving files and directories over HTTP.
class FileHandler {
  /// The root path from which files are served.
  final String rootPath;

  /// The file system to use.
  final file.FileSystem fileSystem;

  /// Whether directory listing is allowed.
  final bool allowDirectoryListing;

  /// Private constructor that takes normalized path.
  const FileHandler._({
    required this.rootPath,
    required this.fileSystem,
    required this.allowDirectoryListing,
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
  }) {
    final currentDir = p.normalize(fileSystem.currentDirectory.path);
    final normalizedPath = p.normalize(
      p.isAbsolute(rootPath) ? rootPath : p.join(currentDir, rootPath),
    );

    return FileHandler._(
      rootPath: normalizedPath,
      fileSystem: fileSystem,
      allowDirectoryListing: allowDirectoryListing,
    );
  }

  /// Factory constructor that creates a [FileHandler] from a [Dir] instance.
  ///
  /// The [dir] parameter specifies the directory from which files are served.
  factory FileHandler.fromDir(Dir dir) {
    final currentDir = p.normalize(dir.fileSystem.currentDirectory.path);
    final normalizedPath = p.normalize(
      p.isAbsolute(dir.path) ? dir.path : p.join(currentDir, dir.path),
    );

    return FileHandler._(
      rootPath: normalizedPath,
      fileSystem: dir.fileSystem,
      allowDirectoryListing: dir.listDirectory,
    );
  }

  /// Serves a file over HTTP.
  ///
  /// The [request] parameter specifies the HTTP request.
  /// The [file] parameter specifies the file to serve.
  Future<void> serveFile(EngineContext ctx, String file) async {
    // removed direct request reference
    try {
      final filePath = p.normalize(p.join(rootPath, file));

      // Robust security check to prevent directory traversal
      if (rootPath != filePath && !p.isWithin(rootPath, filePath)) {
        ctx.abortWithStatus(
          HttpStatus.forbidden,
          ctx.method == 'HEAD' ? '' : 'Access denied',
        );
        return;
      }

      final fileStat = await fileSystem.stat(filePath);

      if (fileStat.type == FileSystemEntityType.directory) {
        await serveDirectory(ctx, filePath, file);
      } else if (fileStat.type == FileSystemEntityType.file) {
        await _serveFile(ctx, filePath, fileStat);
      } else {
        ctx.abortWithStatus(
          HttpStatus.notFound,
          ctx.method == 'HEAD' ? '' : 'Not Found',
        );
      }
    } catch (e) {
      ctx.abortWithStatus(
        HttpStatus.internalServerError,
        'Internal Server Error',
      );
    }
  }

  /// Serves a directory over HTTP.
  ///
  /// The [request] parameter specifies the HTTP request.
  /// The [dirPath] parameter specifies the directory to serve.
  Future<void> serveDirectory(
    EngineContext ctx,
    String dirPath, [
    String parent = '',
  ]) async {
    // First try to serve index.html if it exists
    final indexPath = p.join(p.join(rootPath, dirPath), 'index.html');

    try {
      final indexFileStat = await fileSystem.stat(indexPath);
      if (indexFileStat.type == FileSystemEntityType.file) {
        await _serveFile(ctx, indexPath, indexFileStat);
        return;
      }
    } catch (_) {
      // No index.html, continue to directory listing check
    }

    // Check if directory listing is allowed
    if (!allowDirectoryListing) {
      ctx.abortWithStatus(
        HttpStatus.notFound,
        ctx.method == 'HEAD' ? '' : 'Not Found',
      );
      return;
    }

    await _listDirectory(ctx, dirPath, parent);
  }

  /// Lists the contents of a directory over HTTP.
  ///
  /// The [request] parameter specifies the HTTP request.
  /// The [dirPath] parameter specifies the directory to list.
  Future<void> _listDirectory(
    EngineContext ctx,
    String dirPath, [
    String? parent,
  ]) async {
    final directory = fileSystem.directory(p.join(rootPath, dirPath));
    final entities = await directory.list().toList();

    // Directory listing should explicitly send text/html with utf-8 charset
    ctx.setHeader(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
    ctx.response.write('<!DOCTYPE html><html><body><ul>');

    for (var entity in entities) {
      final name = p.basename(entity.path);
      final isDir = await FileSystemEntity.isDirectory(entity.path);
      final displayName = isDir ? '${entity.parent.basename}/$name/' : name;
      final prefix = (parent != null && parent.isNotEmpty) ? '$parent/' : '';
      final encodedName = Uri.encodeComponent("$prefix$name");
      ctx.response.write('<li><a href="$encodedName">$displayName</a></li>');
    }

    ctx.response.write('</ul></body></html>');
    ctx.response.close();
  }

  /// Serves a file over HTTP.
  ///
  /// The [request] parameter specifies the HTTP request.
  /// The [filePath] parameter specifies the file path to serve.
  /// The [fileStat] parameter specifies the file statistics.
  Future<void> _serveFile(EngineContext ctx,
      String filePath,
      FileStat fileStat,) async {
    final file = fileSystem.file(p.join(rootPath, filePath));

    // Conditional request handling
    if (_handleIfModifiedSince(ctx, fileStat.modified)) {
      return;
    }

    final length = fileStat.size;
    final contentType = _getContentType(file.path);

    ctx.setHeader(HttpHeaders.contentTypeHeader, contentType.toString());

    ctx.setHeader(HttpHeaders.contentLengthHeader, length.toString());
    ctx.setHeader(
      HttpHeaders.lastModifiedHeader,
      HttpDate.format(fileStat.modified),
    );

    // Range request support
    final range = ctx.headers.value(HttpHeaders.rangeHeader);
    final isHead = ctx.method == 'HEAD';
    if (isHead) {
      // Close early after writing headers; no body
      ctx.abort();
      return;
    }

    if (range != null) {
      await _handleRangeRequest(ctx, file, length, range);
    } else {
      // Serve entire file efficiently
      await ctx.response.addStream(file.openRead());
      ctx.response.close();
    }
  }

  /// Handles conditional requests based on the If-Modified-Since header.
  ///
  /// The [ctx] parameter specifies the engine context.
  /// The [lastModified] parameter specifies the last modified date of the file.
  /// Returns true if the file has not been modified since the specified date.
  bool _handleIfModifiedSince(EngineContext ctx, DateTime lastModified) {
    final ifModifiedSince = ctx.request.headers.ifModifiedSince;
    if (ifModifiedSince != null) {
      final lastModifiedTruncated =
          lastModified.toUtc().millisecondsSinceEpoch ~/ 1000;
      final imsTruncated =
          ifModifiedSince.toUtc().millisecondsSinceEpoch ~/ 1000;
      if (lastModifiedTruncated <= imsTruncated) {
        ctx.response.statusCode = HttpStatus.notModified;
        ctx.response.close();
        return true;
      }
    }
    return false;
  }

  /// Handles range requests for partial content delivery.
  ///
  /// The [request] parameter specifies the HTTP request.
  /// The [file] parameter specifies the file to serve.
  /// The [fileLength] parameter specifies the length of the file.
  /// The [rangeHeader] parameter specifies the range header value.
  Future<void> _handleRangeRequest(
    EngineContext ctx,
    File file,
    int fileLength,
    String rangeHeader,
  ) async {
    final ranges = _parseRangeHeader(rangeHeader, fileLength);
    if (ranges == null || ranges.isEmpty) {
      ctx.setHeader(HttpHeaders.contentRangeHeader, 'bytes */$fileLength');
      ctx.abortWithStatus(
        HttpStatus.requestedRangeNotSatisfiable,
        'Requested Range Not Satisfiable',
      );
      return;
    }

    if (ranges.length == 1) {
      final range = ranges[0];
      ctx.response.statusCode = HttpStatus.partialContent;
      ctx.setHeader(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$fileLength',
      );
      ctx.setHeader(
        HttpHeaders.contentLengthHeader,
        (range.end - range.start + 1).toString(),
      );

      await ctx.response.addStream(file.openRead(range.start, range.end + 1));
      ctx.response.close();
    } else {
      ctx.abortWithStatus(
        HttpStatus.notImplemented,
        'Multiple Ranges Not Supported',
      );
    }
  }

  /// Parses the range header to extract byte ranges.
  ///
  /// The [header] parameter specifies the range header value.
  /// The [fileLength] parameter specifies the length of the file.
  /// Returns a list of [_ByteRange] instances or null if the header is invalid.
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

  /// Parses a single range string to extract the byte range.
  ///
  /// The [rangeStr] parameter specifies the range string.
  /// The [fileLength] parameter specifies the length of the file.
  /// Returns a [_ByteRange] instance or null if the range string is invalid.
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

  /// Gets the content type of a file based on its path.
  ///
  /// The [filePath] parameter specifies the file path.
  /// Returns the content type of the file.
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
  ///
  /// The [start] parameter specifies the start byte of the range.
  /// The [end] parameter specifies the end byte of the range.
  _ByteRange(this.start, this.end);
}
