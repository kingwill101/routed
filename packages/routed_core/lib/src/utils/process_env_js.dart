import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Process environment from Node/Bun/Deno-style `globalThis.process.env`.
Map<String, String> readProcessEnvironment() {
  try {
    final process = globalContext.getProperty('process'.toJS);
    if (process == null) return const <String, String>{};

    final envAny = (process as JSObject).getProperty('env'.toJS);
    if (envAny == null) return const <String, String>{};

    final env = envAny as JSObject;
    final objectCtor = globalContext.getProperty('Object'.toJS);
    if (objectCtor == null) return const <String, String>{};

    final keysMethod =
        (objectCtor as JSObject).getProperty('keys'.toJS) as JSFunction?;
    if (keysMethod == null) return const <String, String>{};

    final keysResult = keysMethod.callAsFunction(objectCtor, env);
    if (keysResult == null || !keysResult.isA<JSArray>()) {
      return const <String, String>{};
    }

    final keys = keysResult as JSArray;
    final out = <String, String>{};
    final len = keys.length;
    for (var i = 0; i < len; i++) {
      final keyAny = keys.getProperty(i.toJS);
      if (keyAny == null) continue;
      final key = keyAny.isA<JSString>()
          ? (keyAny as JSString).toDart
          : keyAny.toString();
      final valueAny = env.getProperty(key.toJS);
      if (valueAny == null) continue;
      out[key] = valueAny.isA<JSString>()
          ? (valueAny as JSString).toDart
          : valueAny.toString();
    }
    return out;
  } catch (_) {
    return const <String, String>{};
  }
}

bool get hostIsWindows {
  try {
    final process = globalContext.getProperty('process'.toJS);
    if (process == null) return false;
    final platform = (process as JSObject).getProperty('platform'.toJS);
    if (platform == null) return false;
    final name = platform.isA<JSString>()
        ? (platform as JSString).toDart
        : platform.toString();
    return name == 'win32';
  } catch (_) {
    return false;
  }
}
