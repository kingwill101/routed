import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:server_testing/src/browser/bootstrap/browsers_json_const.dart';

import 'browser_json.dart';

/// Loads the `browsers.json` configuration file.
class BrowserJsonLoader {
  /// Loads the [BrowserJson] configuration from `browsers.json` located in
  /// the current working directory.
  ///
  /// If the `browsers.json` file is not found, it falls back to loading a
  /// default configuration defined in [browserJsonData].
  static Future<BrowserJson> load() async {
    final file = File(path.join(Directory.current.path, 'browsers.json'));

    if (!await file.exists()) {
      print('No browsers.json found, using default configuration');
      return _createDefaultConfig();
    }

    final content = await file.readAsString();
    return BrowserJson.fromJson(json.decode(content) as Map<String, dynamic>);
  }

  /// Creates a default [BrowserJson] configuration using the embedded data
  /// from `browsers_json_const.dart`.
  static BrowserJson _createDefaultConfig() {
    return browserJsonData;
  }
}
