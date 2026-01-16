part of 'context.dart';

/// Extension providing Server-Sent Events (SSE) support for [EngineContext].
///
/// This extension enables real-time server-to-client communication using the
/// SSE protocol, which allows servers to push updates to clients over a single
/// HTTP connection. SSE is ideal for one-way real-time updates like live feeds,
/// notifications, or progress indicators.
///
/// ## Features
///
/// - **Automatic Heartbeats**: Keeps connections alive with periodic heartbeat comments
/// - **Graceful Shutdown**: Closes connections cleanly when the server shuts down
/// - **Compression Disabled**: Automatically disables compression for streaming
/// - **Buffering Control**: Disables output buffering for immediate delivery
///
/// Example:
/// ```dart
/// engine.get('/events', (context) async {
///   final events = Stream.periodic(
///     Duration(seconds: 1),
///     (count) => SseEvent(data: 'Update $count'),
///   );
///
///   await context.sse(events);
/// });
/// ```
extension EngineContextSse on EngineContext {
  /// Establishes an SSE connection and streams events to the client.
  ///
  /// This method sets up an SSE connection with proper headers, handles the
  /// event stream, and manages connection lifecycle including heartbeats and
  /// graceful shutdown. The connection remains open until the event stream
  /// completes, an error occurs, or the client disconnects.
  ///
  /// The [events] stream provides the SSE events to send to the client. Each
  /// event is encoded according to the SSE specification and flushed immediately.
  ///
  /// The [heartbeat] duration controls how often heartbeat comments are sent
  /// to keep the connection alive and detect disconnections. Set to [Duration.zero]
  /// to disable heartbeats. Default is 15 seconds.
  ///
  /// The [heartbeatComment] is the text included in heartbeat comment lines.
  /// Default is 'heartbeat'.
  ///
  /// Example with custom heartbeat:
  /// ```dart
  /// engine.get('/notifications', (context) async {
  ///   final notifications = getNotificationStream();
  ///
  ///   await context.sse(
  ///     notifications,
  ///     heartbeat: Duration(seconds: 30),
  ///     heartbeatComment: 'ping',
  ///   );
  /// });
  /// ```
  ///
  /// Example with real-time data:
  /// ```dart
  /// engine.get('/stock-prices', (context) async {
  ///   final symbol = context.request.uri.queryParameters['symbol'];
  ///   final prices = stockService.watchPrice(symbol).map(
  ///     (price) => SseEvent(
  ///       event: 'price-update',
  ///       data: json.encode({'symbol': symbol, 'price': price}),
  ///     ),
  ///   );
  ///
  ///   await context.sse(prices);
  /// });
  /// ```
  ///
  /// The connection is automatically closed when:
  /// - The event stream completes normally
  /// - The event stream emits an error
  /// - The client disconnects
  /// - The server initiates graceful shutdown
  /// - An [HttpException] occurs during writing
  Future<void> sse(
    Stream<SseEvent> events, {
    Duration heartbeat = const Duration(seconds: 15),
    String heartbeatComment = 'heartbeat',
  }) async {
    disableCompression(this);

    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform')
      ..set('X-Accel-Buffering', 'no');

    response.writeHeaderNow();

    // Disable output buffering so subsequent writes stream immediately.
    response.bufferOutput = false;

    // Prime the stream with a comment so intermediaries release the response.
    response.write(':ok\n\n');
    await response.flush();
    response.writeNow(); // mark response as streaming

    final codec = SseCodec();
    Timer? heartbeatTimer; // Timer for periodic heartbeat comments
    Timer? shutdownPollTimer; // Timer for polling shutdown state
    bool closed = false; // Whether the connection has been closed
    bool shutdownSignaled = false; // Whether shutdown control event was sent
    StreamSubscription<SseEvent>? subscription; // Event stream subscription
    final completion = Completer<void>(); // Tracks connection completion

    // Writes a raw SSE frame to the response stream
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

    // Encodes and writes an SSE event
    Future<void> writeEvent(SseEvent event) {
      return writeFrame(codec.encode(event));
    }

    // Writes a heartbeat comment to keep the connection alive
    Future<void> writeHeartbeat() async {
      try {
        await writeFrame(':$heartbeatComment\n\n');
      } catch (_) {}
    }

    // Closes the SSE connection and cleans up resources
    Future<void> closeConnection({bool fromSubscription = false}) async {
      if (closed) {
        return;
      }
      closed = true;
      heartbeatTimer?.cancel();
      shutdownPollTimer?.cancel();
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
      if (!completion.isCompleted) {
        completion.complete();
      }
    }

    response.done.catchError((_) {}).whenComplete(() {
      if (!completion.isCompleted) {
        completion.complete();
      }
    });

    // Subscribe to the event stream and forward events to the client
    subscription = events.listen(
      (event) async {
        if (closed) {
          return;
        }
        try {
          await writeEvent(event);
        } on HttpException {
          await closeConnection(fromSubscription: true);
        }
      },
      onError: (_, _) async {
        await closeConnection(fromSubscription: true);
      },
      onDone: () async {
        await closeConnection(fromSubscription: true);
      },
      cancelOnError: false,
    );

    // Start periodic heartbeat if enabled
    if (heartbeat > Duration.zero) {
      heartbeatTimer = Timer.periodic(heartbeat, (_) {
        if (!closed) {
          unawaited(writeHeartbeat());
        }
      });
    }

    // Poll shutdown controller to promptly close SSE connections during graceful shutdown
    final sc = engine?.shutdownController;
    if (sc != null) {
      shutdownPollTimer = Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) async {
        if (closed) {
          shutdownPollTimer?.cancel();
          return;
        }
        final controller = engine?.shutdownController;
        if (controller == null) return;
        if (controller.isDraining && !shutdownSignaled) {
          shutdownSignaled = true;
          // Send a control event to notify clients of shutdown
          try {
            await writeEvent(
              SseEvent(event: 'control', data: 'close', retry: Duration.zero),
            );
          } catch (_) {}
          await closeConnection();
        }
      });
    }

    try {
      await completion.future;
    } finally {
      await closeConnection();
    }
  }
}
