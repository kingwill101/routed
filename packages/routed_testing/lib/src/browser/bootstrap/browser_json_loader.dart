import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:routed_testing/src/browser/bootstrap/browsers_json_const.dart';

import 'browser_json.dart';

class BrowserJsonLoader {
  static Future<BrowserJson> load() async {
    final file = File(path.join(Directory.current.path, 'browsers.json'));

    if (!await file.exists()) {
      print('No browsers.json found, using default configuration');
      return _createDefaultConfig();
    }

    final content = await file.readAsString();
    return BrowserJson.fromJson(json.decode(content) as Map<String, dynamic>);
  }

  static BrowserJson _createDefaultConfig() {
    return browserJsonData;
  }
}
