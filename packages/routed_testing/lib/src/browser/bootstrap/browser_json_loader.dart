import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'browser_json.dart';

class BrowserJsonLoader {
  static Future<BrowserJson> load() async {
    final file = File(path.join(Directory.current.path, 'browsers.json'));

    // If file doesn't exist, return default configuration
    if (!await file.exists()) {
      print('No browsers.json found, using default configuration');
      return _createDefaultConfig();
    }

    final content = await file.readAsString();
    return BrowserJson.fromJson(json.decode(content) as Map<String, dynamic>);
  }

  static BrowserJson _createDefaultConfig() {
    return BrowserJson(
      comment: 'Default browser configuration',
      browsers: [
        BrowserEntry(
          name: 'firefox',
          revision: 'latest',
          browserVersion: '121.0',
          installByDefault: true,
          revisionOverrides: null,
        ),
        BrowserEntry(
          name: 'chrome',
          revision: 'latest',
          browserVersion: '121.0',
          installByDefault: true,
          revisionOverrides: null,
        ),
      ],
    );
  }
}
