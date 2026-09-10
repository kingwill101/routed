import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Reads Node/Bun/Deno-style command-line arguments from `process.argv`.
///
/// Dart2JS invokes `main` with an empty argument list, so standalone Node
/// entrypoints use this helper when they need to dispatch a command after
/// compilation.
List<String> readNodeProcessArguments() {
  try {
    final process = globalContext.getProperty('process'.toJS);
    if (process == null) return const <String>[];
    final argvAny = (process as JSObject).getProperty('argv'.toJS);
    if (argvAny == null || !argvAny.isA<JSArray>()) {
      return const <String>[];
    }
    final argv = argvAny as JSArray;
    final out = <String>[];
    for (var i = 2; i < argv.length; i++) {
      final value = argv.getProperty(i.toJS);
      if (value == null) continue;
      out.add(
        value.isA<JSString>() ? (value as JSString).toDart : value.toString(),
      );
    }
    return out;
  } catch (_) {
    return const <String>[];
  }
}
