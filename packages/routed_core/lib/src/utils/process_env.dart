/// Best-effort process environment and host OS flags used by core internals.
///
/// Application and adapter configuration should use the typed runtime
/// environment source instead of reading this low-level compatibility surface
/// directly.
///
/// - VM: `dart:io` [Platform.environment]
/// - Node/JS: `process.env` via js_interop
/// - else: empty map
///
/// Never throws on unsupported hosts (returns empty / false).
library;

import 'dart:io' show Platform;

export 'process_env_stub.dart'
    if (dart.library.io) 'process_env_io.dart'
    if (dart.library.js_util) 'process_env_js.dart';
