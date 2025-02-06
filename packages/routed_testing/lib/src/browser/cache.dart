import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

class BrowserCache {
  final String cacheDir;

  BrowserCache(this.cacheDir);

  Future<void> init() async {
    await Directory(cacheDir).create(recursive: true);
  }

  String _getCacheKey(String url) {
    return sha256.convert(utf8.encode(url)).toString();
  }

  Future<File?> getCachedFile(String url) async {
    final key = _getCacheKey(url);
    final file = File(path.join(cacheDir, key));
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<void> cacheFile(String url, List<int> bytes) async {
    final key = _getCacheKey(url);
    final file = File(path.join(cacheDir, key));
    await file.writeAsBytes(bytes);
  }

  Future<void> clear() async {
    if (await Directory(cacheDir).exists()) {
      await Directory(cacheDir).delete(recursive: true);
    }
  }
}
