import 'package:server_testing/src/browser/browser_config.dart';

/// Resolves a potentially relative [url] against the `baseUrl` provided in the [config].
///
/// If the [url] already starts with 'http://' or 'https://', it is returned directly.
/// Otherwise, if a non-empty `baseUrl` exists in the [config], the [url] is
/// treated as a path and appended to the `baseUrl`. Ensures proper handling of
/// trailing/leading slashes.
///
/// Returns the absolute URL string.
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
