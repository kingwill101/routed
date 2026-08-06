// SSE helpers for EngineContext per refactor.md §11.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';

import '../binding/convert/sse.dart';

extension RoutedHttpSse on EngineContext {
  Future<void> sse(
    Stream<SseEvent> events, {
    Duration heartbeat = const Duration(seconds: 15),
    String heartbeatComment = 'heartbeat',
  }) async {
    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform')
      ..set('X-Accel-Buffering', 'no');
    response.writeHeaderNow();
    response.bufferOutput = false;
    response.write(':ok\n\n');
    await response.flush();
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    response.writeNow();
    final codec = SseCodec();
    Timer? heartbeatTimer;
    bool closed = false;
    StreamSubscription<SseEvent>? subscription;
    final completion = Completer<void>();

    Future<void> writeFrame(String frame) async {
      if (response.isClosed) {
        closed = true;
        return;
      }
      response.writeBytes(utf8.encode(frame));
      try {
        await response.flush();
      } on HttpException {
        closed = true;
        rethrow;
      }
    }

    Future<void> writeEvent(SseEvent event) => writeFrame(codec.encode(event));

    Future<void> writeHeartbeat() async {
      try {
        await writeFrame(':$heartbeatComment\n\n');
      } catch (_) {}
    }

    Future<void> closeConnection({bool fromSubscription = false}) async {
      if (closed) return;
      closed = true;
      heartbeatTimer?.cancel();
      if (!fromSubscription) {
        try {
          await subscription?.cancel();
        } catch (_) {}
      }
      if (!response.isClosed) {
        try {
          await response.close();
        } catch (_) {}
      }
      if (!completion.isCompleted) completion.complete();
    }

    response.done.catchError((_) {}).whenComplete(() {
      if (!completion.isCompleted) completion.complete();
    });

    subscription = events.listen(
      (event) async {
        if (closed) return;
        try {
          await writeEvent(event);
        } on HttpException {
          await closeConnection(fromSubscription: true);
        }
      },
      onError: (_, _) async => await closeConnection(fromSubscription: true),
      onDone: () async => await closeConnection(fromSubscription: true),
      cancelOnError: false,
    );

    if (heartbeat > Duration.zero) {
      heartbeatTimer = Timer.periodic(heartbeat, (_) {
        if (!closed) unawaited(writeHeartbeat());
      });
    }

    try {
      await completion.future;
    } finally {
      await closeConnection();
    }
  }
}
