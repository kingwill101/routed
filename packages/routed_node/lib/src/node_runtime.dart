// Conditional Node runtime:
// - JS targets (`dart.library.js_util`): real `http.createServer` interop
// - Dart VM: stub that explains how to compile for Node
export 'node_runtime_stub.dart' if (dart.library.js_util) 'node_runtime_js.dart';
