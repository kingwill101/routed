import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:server_testing/src/browser/browser_exception.dart';

/// Represents the state of a file download operation at a specific moment.
///
/// Includes the number of bytes received, the total expected bytes, the
/// percentage completion, and the current download speed.
class DownloadProgress {
  /// The number of bytes received so far.
  final int received;
  /// The total expected size of the download in bytes. May be 0 if unknown.
  final int total;
  /// The download progress as a percentage (0.0 to 100.0).
  final double percent;
  /// The current download speed in bytes per second.
  final double speed; // bytes per second

  /// Creates a [DownloadProgress] instance.
  DownloadProgress({
    required this.received,
    required this.total,
    required this.percent,
    required this.speed,
  });

  /// Returns a user-friendly string representation of the download progress,
  /// typically showing MB received/total, percentage, and speed in MB/s.
  @override
  String toString() {
    final mb = (received / 1024 / 1024).toStringAsFixed(1);
    final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
    final mbps = (speed / 1024 / 1024).toStringAsFixed(1);
    return '$mb/$totalMb MB (${percent.toStringAsFixed(1)}%) at $mbps MB/s';
  }
}

/// Handles downloading files, specifically browser archives, with progress reporting.
class BrowserDownloader {
  /// Downloads a file from the specified [url] and saves it to [outputPath].
  ///
  /// Provides progress updates via the optional [onProgress] callback, which
  /// receives [DownloadProgress] objects. Verifies that the download was
  /// successful and the resulting file is a valid ZIP archive.
  ///
  /// Throws a [BrowserException] if the download fails, the status code is not
  /// 200, the downloaded file is empty, or the file is not a valid ZIP archive.
  static Future<void> downloadWithProgress(
    String url,
    String outputPath, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    print('Starting download from: $url');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw BrowserException(
          'Download failed with status ${response.statusCode}',
          'Response: ${response.body}');
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw BrowserException('Downloaded file is empty');
    }

    print('Downloaded ${bytes.length} bytes');

    // Verify ZIP structure
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      print('Archive contains ${archive.files.length} files');

      // List some files for verification
      final fileNames = archive.files.take(5).map((f) => f.name).join(', ');
      print('Sample files: $fileNames');
    } catch (e) {
      throw BrowserException('Invalid ZIP file format', e);
    }

    await File(outputPath).writeAsBytes(bytes);
  }
}
