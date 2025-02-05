import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:routed_testing/src/browser/browser_exception.dart';

class DownloadProgress {
  final int received;
  final int total;
  final double percent;
  final double speed; // bytes per second

  DownloadProgress({
    required this.received,
    required this.total,
    required this.percent,
    required this.speed,
  });

  @override
  String toString() {
    final mb = (received / 1024 / 1024).toStringAsFixed(1);
    final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
    final mbps = (speed / 1024 / 1024).toStringAsFixed(1);
    return '$mb/$totalMb MB (${percent.toStringAsFixed(1)}%) at $mbps MB/s';
  }
}

class BrowserDownloader {
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
        'Response: ${response.body}'
      );
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