import 'dart:async';
import 'dart:convert';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:server_storage/src/static_file_sink.dart';
import 'package:server_storage/src/storage_signed_url.dart';
import 'package:storage_fs/storage_fs.dart' show Filesystem, FilesystemAdapter;

/// Serves static HTTP responses from a `storage_fs` filesystem.
///
/// This complements `FileHandler` for asynchronous or host-native backends
/// that cannot expose `package:file`, including Cloudflare R2 bindings.
final class StorageFileHandler {
  /// Creates a handler rooted at [rootPath] within [storage].
  ///
  /// [rootPath] and every request path must remain relative to the filesystem
  /// root. Only objects reporting public visibility are served. Directory
  /// indexes and listings use [indexFile] and [allowDirectoryListing].
  StorageFileHandler({
    required this.storage,
    String rootPath = '',
    this.allowDirectoryListing = false,
    this.indexFile = 'index.html',
    this.directoryExists,
  }) : rootPath = _normalizeRoot(rootPath),
       _requirePublicVisibility = true;

  StorageFileHandler._authorized({
    required this.storage,
    required String rootPath,
    required this.indexFile,
    required this.directoryExists,
  }) : rootPath = _normalizeRoot(rootPath),
       allowDirectoryListing = false,
       _requirePublicVisibility = false;

  /// Filesystem supplying static objects and metadata.
  final Filesystem storage;

  /// Normalized relative directory containing mounted objects.
  final String rootPath;

  /// Whether requests without a file or index may list directory entries.
  final bool allowDirectoryListing;

  /// File served for directory requests, or an empty string to disable it.
  final String indexFile;

  /// Optional asynchronous directory probe for hierarchical filesystems.
  ///
  /// Object stores generally do not need this because directories are virtual.
  /// Filesystem adapters can supply it to distinguish a directory from a file
  /// when both are reported by `Filesystem.exists()`.
  final Future<bool> Function(String path)? directoryExists;

  /// Whether the handler must observe public object visibility.
  ///
  /// Ordinary static mounts always require public visibility. The private
  /// mode is only constructed internally by [SignedStorageFileHandler], which
  /// verifies a capability URL before performing any storage operation.
  final bool _requirePublicVisibility;

  /// Serves [requestedPath] through [sink].
  ///
  /// When [requestUrl] is supplied, directory-listing links are rooted at the
  /// current request path so they work with or without a trailing slash.
  Future<void> serveFile(
    StaticFileSink sink,
    String requestedPath, {
    Uri? requestUrl,
  }) async {
    final relative = _normalizeRequestPath(requestedPath);
    if (relative == null) {
      _abort(sink, _forbidden, 'Access denied');
      return;
    }

    try {
      if (await _isDirectory(relative, requestedPath)) {
        await _serveDirectory(sink, relative, requestUrl);
        return;
      }
      if (relative.isNotEmpty && await storage.exists(relative)) {
        await _serveObject(sink, relative);
        return;
      }
      await _serveDirectory(sink, relative, requestUrl);
    } on Object {
      _abort(sink, _internalServerError, 'Internal Server Error');
    }
  }

  Future<bool> _isDirectory(String relative, String requestedPath) async {
    if (requestedPath.isEmpty || requestedPath.endsWith('/')) return true;

    final probe = directoryExists;
    if (probe != null && await probe(relative)) return true;

    final filesystem = storage;
    if (filesystem is FilesystemAdapter &&
        await filesystem.directoryExists(relative)) {
      return true;
    }
    return false;
  }

  Future<void> _serveDirectory(
    StaticFileSink sink,
    String directory,
    Uri? requestUrl,
  ) async {
    final indexPath = indexFile.isEmpty
        ? null
        : path.posix.join(directory, indexFile);
    if (indexPath != null && await storage.exists(indexPath)) {
      await _serveObject(sink, indexPath);
      return;
    }

    if (!allowDirectoryListing) {
      _abort(sink, _notFound, 'Not Found');
      return;
    }

    final listingDirectory = directory.isEmpty && storage is FilesystemAdapter
        ? '.'
        : directory;
    final rawFiles = (await storage.files(listingDirectory))
        .map((entry) => _normalizeListedPath(entry, directory))
        .whereType<String>()
        .toList(growable: false);
    final rawDirectories = (await storage.directories(listingDirectory))
        .map((entry) => _normalizeListedPath(entry, directory))
        .whereType<String>()
        .toList(growable: false);
    final files = _requirePublicVisibility
        ? await _publicFiles(rawFiles)
        : rawFiles;
    final directories = _requirePublicVisibility
        ? await _publicDirectories(rawDirectories)
        : rawDirectories;
    if (files.isEmpty && directories.isEmpty) {
      _abort(sink, _notFound, 'Not Found');
      return;
    }

    final entries = <({String name, bool directory})>[
      ...directories.map(
        (entry) => (name: path.posix.basename(entry), directory: true),
      ),
      ...files.map(
        (entry) => (name: path.posix.basename(entry), directory: false),
      ),
    ]..sort((a, b) => a.name.compareTo(b.name));

    sink
      ..setHeader(_contentTypeHeader, 'text/html; charset=utf-8')
      ..write('<!DOCTYPE html><html><body><ul>');
    const escape = HtmlEscape(HtmlEscapeMode.element);
    final basePath = switch (requestUrl?.path) {
      final value? when value.endsWith('/') => value,
      final value? => '$value/',
      null => '',
    };
    for (final entry in entries) {
      final suffix = entry.directory ? '/' : '';
      final label = escape.convert('${entry.name}$suffix');
      final href = Uri(path: '$basePath${entry.name}$suffix').toString();
      sink.write('<li><a href="$href">$label</a></li>');
    }
    sink.write('</ul></body></html>');
    await sink.close();
  }

  Future<void> _serveObject(StaticFileSink sink, String objectPath) async {
    if (_requirePublicVisibility && !await _isPublic(objectPath)) {
      _abort(sink, _notFound, 'Not Found');
      return;
    }
    final size = await storage.size(objectPath);
    final modified = await storage.lastModified(objectPath);
    if (_handleIfModifiedSince(sink, modified)) return;

    final mimeType =
        await storage.mimeType(objectPath) ??
        lookupMimeType(objectPath) ??
        'application/octet-stream';
    sink
      ..setHeader(_contentTypeHeader, mimeType)
      ..setHeader(_contentLengthHeader, size.toString())
      ..setHeader(_lastModifiedHeader, _formatHttpDate(modified));

    if (sink.method == 'HEAD') {
      sink.abort();
      return;
    }

    final stream = storage.readStream(objectPath);
    if (stream == null) {
      _abort(sink, _notFound, 'Not Found');
      return;
    }

    final rangeHeader = sink.headers.value(_rangeHeader);
    if (rangeHeader == null) {
      await sink.addStream(stream);
      await sink.close();
      return;
    }

    final ranges = _parseRangeHeader(rangeHeader, size);
    if (ranges == null || ranges.isEmpty) {
      sink
        ..setHeader(_contentRangeHeader, 'bytes */$size')
        ..abortWithStatus(
          _requestedRangeNotSatisfiable,
          'Requested Range Not Satisfiable',
        );
      return;
    }
    if (ranges.length > 1) {
      _abort(sink, _notImplemented, 'Multiple Ranges Not Supported');
      return;
    }

    final range = ranges.single;
    sink
      ..statusCode = _partialContent
      ..setHeader(
        _contentRangeHeader,
        'bytes ${range.start}-${range.end}/$size',
      )
      ..setHeader(
        _contentLengthHeader,
        (range.end - range.start + 1).toString(),
      );
    await sink.addStream(_slice(stream, range.start, range.end));
    await sink.close();
  }

  Future<List<String>> _publicFiles(Iterable<String> files) async {
    final visible = <String>[];
    for (final file in files) {
      if (await _isPublic(file)) visible.add(file);
    }
    return visible;
  }

  Future<List<String>> _publicDirectories(Iterable<String> directories) async {
    final visible = <String>[];
    for (final directory in directories) {
      try {
        final descendants = await storage.allFiles(directory);
        var containsPublicObject = false;
        for (final rawFile in descendants) {
          final file = _normalizeListedPath(rawFile, directory);
          if (file != null && await _isPublic(file)) {
            containsPublicObject = true;
            break;
          }
        }
        if (containsPublicObject) visible.add(directory);
      } on Object {
        // Visibility and listing errors fail closed without revealing names.
      }
    }
    return visible;
  }

  Future<bool> _isPublic(String objectPath) async {
    try {
      return await storage.getVisibility(objectPath) ==
          Filesystem.visibilityPublic;
    } on Object {
      return false;
    }
  }

  String? _normalizeListedPath(String value, String directory) {
    var relative = value.replaceAll(r'\', '/');
    while (relative.startsWith('/')) {
      relative = relative.substring(1);
    }
    final normalized = path.posix.normalize(relative);
    if (normalized.isEmpty ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      return null;
    }
    if (directory.isNotEmpty &&
        normalized != directory &&
        !normalized.startsWith('$directory/')) {
      return null;
    }
    return normalized;
  }

  bool _handleIfModifiedSince(StaticFileSink sink, DateTime lastModified) {
    final ifModifiedSince = sink.headers.ifModifiedSince;
    if (ifModifiedSince == null) return false;
    final modifiedSeconds = lastModified.toUtc().millisecondsSinceEpoch ~/ 1000;
    final requestedSeconds =
        ifModifiedSince.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (modifiedSeconds > requestedSeconds) return false;
    sink.statusCode = _notModified;
    unawaited(sink.close());
    return true;
  }

  Stream<List<int>> _slice(
    Stream<List<int>> source,
    int start,
    int end,
  ) async* {
    var offset = 0;
    var remaining = end - start + 1;
    await for (final chunk in source) {
      final chunkEnd = offset + chunk.length;
      if (chunkEnd <= start) {
        offset = chunkEnd;
        continue;
      }
      final localStart = start > offset ? start - offset : 0;
      final available = chunk.length - localStart;
      final count = available < remaining ? available : remaining;
      if (count > 0) {
        yield chunk.sublist(localStart, localStart + count);
        remaining -= count;
      }
      if (remaining == 0) return;
      offset = chunkEnd;
    }
  }

  List<_ByteRange>? _parseRangeHeader(String header, int fileLength) {
    if (!header.startsWith('bytes=')) return null;
    final ranges = <_ByteRange>[];
    for (final value in header.substring(6).split(',')) {
      final range = _parseRange(value.trim(), fileLength);
      if (range != null) ranges.add(range);
    }
    return ranges;
  }

  _ByteRange? _parseRange(String value, int fileLength) {
    final parts = value.split('-');
    if (parts.length != 2 || fileLength <= 0) return null;
    var start = parts.first.isEmpty ? null : int.tryParse(parts.first);
    var end = parts.last.isEmpty ? null : int.tryParse(parts.last);
    if ((parts.first.isNotEmpty && start == null) ||
        (parts.last.isNotEmpty && end == null)) {
      return null;
    }
    if (start == null) {
      if (end == null || end <= 0) return null;
      start = end >= fileLength ? 0 : fileLength - end;
      end = fileLength - 1;
    } else {
      if (start < 0 || start >= fileLength) return null;
      end = end == null || end >= fileLength ? fileLength - 1 : end;
      if (end < start) return null;
    }
    return _ByteRange(start, end);
  }

  String? _normalizeRequestPath(String value) {
    if (path.posix.isAbsolute(value)) {
      return null;
    }
    final normalized = path.posix.normalize(value);
    if (normalized == '..' || normalized.startsWith('../')) {
      return null;
    }
    final requestPath = normalized == '.' ? '' : normalized;
    return rootPath.isEmpty
        ? requestPath
        : requestPath.isEmpty
        ? rootPath
        : path.posix.join(rootPath, requestPath);
  }

  void _abort(StaticFileSink sink, int status, String message) {
    sink.abortWithStatus(status, sink.method == 'HEAD' ? '' : message);
  }

  static String _normalizeRoot(String value) {
    if (value.isEmpty) return '';
    if (path.posix.isAbsolute(value)) {
      throw ArgumentError.value(value, 'rootPath', 'Must be relative.');
    }
    final normalized = path.posix.normalize(value);
    if (normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(value, 'rootPath', 'Escapes storage root.');
    }
    return normalized == '.' ? '' : normalized;
  }

  static String _formatHttpDate(DateTime value) {
    final date = value.toUtc();
    final weekday = _weekdays[date.weekday - 1];
    final month = _months[date.month - 1];
    return '$weekday, ${_twoDigits(date.day)} $month ${date.year} '
        '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}:'
        '${_twoDigits(date.second)} GMT';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

/// Serves private storage objects only after verifying a signed request URL.
///
/// This is intentionally separate from [StorageFileHandler]: ordinary static
/// mounts can never opt out of public-visibility checks. Applications should
/// authenticate and authorize a user before issuing URLs with [signer].
final class SignedStorageFileHandler {
  /// Creates a signed private-object handler rooted at [rootPath].
  SignedStorageFileHandler({
    required Filesystem storage,
    required this.signer,
    String rootPath = '',
    String indexFile = 'index.html',
    Future<bool> Function(String path)? directoryExists,
  }) : _delegate = StorageFileHandler._authorized(
         storage: storage,
         rootPath: rootPath,
         indexFile: indexFile,
         directoryExists: directoryExists,
       );

  /// Signer used to verify request capability URLs.
  final StorageSignedUrlSigner signer;

  final StorageFileHandler _delegate;

  /// Verifies [requestUrl] before serving [requestedPath].
  Future<void> serveFile(
    StaticFileSink sink,
    String requestedPath, {
    required Uri requestUrl,
  }) async {
    if (!signer.verify(requestUrl, method: sink.method)) {
      sink.abortWithStatus(
        _forbidden,
        sink.method == 'HEAD' ? '' : 'Forbidden',
      );
      return;
    }
    sink.setHeader(_cacheControlHeader, 'private, no-store');
    await _delegate.serveFile(
      sink,
      requestedPath,
      requestUrl: requestUrl,
    );
  }
}

const _contentLengthHeader = 'content-length';
const _cacheControlHeader = 'cache-control';
const _contentRangeHeader = 'content-range';
const _contentTypeHeader = 'content-type';
const _lastModifiedHeader = 'last-modified';
const _rangeHeader = 'range';

const _partialContent = 206;
const _notModified = 304;
const _forbidden = 403;
const _notFound = 404;
const _notImplemented = 501;
const _requestedRangeNotSatisfiable = 416;
const _internalServerError = 500;

const _weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

final class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;
}
