import 'package:routed_core/routed_core.dart';

import '../runtime/runtime.dart';

/// VM stub for JavaScript Fetch exports.
Never defineFetchExport(
  String runtime,
  Engine engine, {
  required RoutedNodeCapabilities capabilities,
  String name = '__routed_fetch__',
}) {
  throw UnsupportedError('$runtime Fetch exports require a JavaScript host.');
}
