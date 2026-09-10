/// Host-process arguments for the Node-family runtime entrypoints.
library;

export 'process_args_stub.dart'
    if (dart.library.js_util) 'process_args_js.dart';
