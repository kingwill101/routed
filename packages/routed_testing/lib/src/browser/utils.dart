import 'package:routed_testing/src/browser/browser_config.dart';

String resolveUrl(String url, {BrowserConfig? config}) {
  String finalUrl = url;
  if (config?.baseUrl != null) {
    if (!(url.startsWith('http://') || url.startsWith('https://')) &&
        config!.baseUrl!.isNotEmpty) {
      final base = config.baseUrl!.endsWith('/')
          ? config.baseUrl!.substring(0, config.baseUrl!.length - 1)
          : config.baseUrl;
      final path = url.startsWith('/') ? url : '/$url';
      finalUrl = '$base$path';
    }
  }
  return finalUrl;
}
