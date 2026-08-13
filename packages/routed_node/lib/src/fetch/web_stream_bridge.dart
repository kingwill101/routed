@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

extension type _UnderlyingSource._(JSObject _) implements JSObject {
  external factory _UnderlyingSource({
    JSFunction? start,
    JSFunction? cancel,
    String? type,
  });
}

Stream<List<int>> dartStreamFromWeb(web.ReadableStream stream) async* {
  final reader = stream.getReader() as web.ReadableStreamDefaultReader;
  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) break;
      final value = result.value;
      if (value == null) continue;
      final bytes = (value as JSUint8Array).toDart;
      if (bytes.isNotEmpty) yield bytes;
    }
  } finally {
    reader.releaseLock();
  }
}

web.ReadableStream webStreamFromDart(Stream<List<int>> stream) {
  StreamSubscription<List<int>>? subscription;

  void start(web.ReadableStreamDefaultController controller) {
    subscription = stream.listen(
      (chunk) {
        if (chunk.isNotEmpty) {
          final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
          controller.enqueue(bytes.toJS);
        }
      },
      onError: (Object error, StackTrace _) =>
          controller.error(error.toString().toJS),
      onDone: () {
        try {
          controller.close();
        } catch (_) {}
      },
    );
  }

  void cancel([JSAny? _]) {
    final active = subscription;
    if (active != null) unawaited(active.cancel());
  }

  return web.ReadableStream(
    _UnderlyingSource(type: 'bytes', start: start.toJS, cancel: cancel.toJS),
  );
}
