import 'dart:convert';

/// Represents an SSE (Server-Sent Events) event.
///
/// This class encapsulates the data structure of an SSE event, which includes
/// optional fields for `id`, `event`, and `retry`, and a required `data` field.
class SseEvent {
  /// The ID of the event. This can be used to re-establish a connection and
  /// continue receiving events from where it left off.
  final String? id;

  /// The type of event. This can be used to categorize events.
  final String? event;

  /// The reconnection time to use when attempting to reconnect after a connection is lost.
  final Duration? retry;

  /// The actual data of the event. This is the main content of the SSE event.
  final String data;

  /// Constructs an [SseEvent] with the given parameters.
  ///
  /// The [data] parameter is required, while [id], [event], and [retry] are optional.
  SseEvent({this.id, this.event, this.retry, required this.data});

  @override
  String toString() {
    return 'SseEvent(id: $id, event: $event, retry: $retry, data: $data)';
  }
}

/// A codec for encoding and decoding SSE events.
///
/// This codec provides a way to convert between raw SSE strings and [SseEvent] objects.
class SseCodec extends Codec<SseEvent, String> {
  /// Returns the decoder that converts raw SSE strings into [SseEvent] objects.
  @override
  Converter<String, SseEvent> get decoder => _SseEventDecoder();

  /// Returns the encoder that converts [SseEvent] objects into raw SSE strings.
  @override
  Converter<SseEvent, String> get encoder => _SseEventEncoder();
}

/// Decodes a raw SSE stream into [SseEvent] objects.
///
/// This class implements the conversion logic from a raw SSE string to an [SseEvent] object.
class _SseEventDecoder extends Converter<String, SseEvent> {
  /// Converts a raw SSE string into an [SseEvent] object.
  ///
  /// The input string is expected to follow the SSE format, with lines starting
  /// with `id:`, `event:`, `retry:`, or `data:`. The method processes each line
  /// and constructs an [SseEvent] object with the extracted values.
  @override
  SseEvent convert(String input) {
    final lines = input.split('\n');
    String? id;
    String? event;
    Duration? retry;
    final dataBuffer = StringBuffer();

    for (var line in lines) {
      if (line.startsWith('id:')) {
        id = line.substring(3).trim();
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('retry:')) {
        final retryValue = int.tryParse(line.substring(6).trim());
        if (retryValue != null) {
          retry = Duration(milliseconds: retryValue);
        }
      } else if (line.startsWith('data:')) {
        dataBuffer.writeln(line.substring(5).trim());
      }
    }

    return SseEvent(
      id: id,
      event: event,
      retry: retry,
      data: dataBuffer.toString().trim(),
    );
  }
}

/// Encodes [SseEvent] objects into SSE-compatible strings.
///
/// This class implements the conversion logic from an [SseEvent] object to a raw SSE string.
class _SseEventEncoder extends Converter<SseEvent, String> {
  /// Converts an [SseEvent] object into a raw SSE string.
  ///
  /// The method constructs a string following the SSE format, with lines starting
  /// with `id:`, `event:`, `retry:`, or `data:`. Each field of the [SseEvent] object
  /// is processed and added to the resulting string.
  @override
  String convert(SseEvent event) {
    final buffer = StringBuffer();

    if (event.id != null) {
      buffer.writeln('id: ${event.id}');
    }
    if (event.event != null) {
      buffer.writeln('event: ${event.event}');
    }
    if (event.retry != null) {
      buffer.writeln('retry: ${event.retry!.inMilliseconds}');
    }
    for (var line in LineSplitter.split(event.data)) {
      buffer.writeln('data: $line');
    }

    buffer.writeln(); // End of the event
    return buffer.toString();
  }
}

void main() {
  // Example usage of SseCodec
  final codec = SseCodec();

  // Decode example
  final rawSse = 'id: 1\nevent: message\ndata: Hello, world!\n\n';
  final decodedEvent = codec.decode(rawSse);
  print('Decoded event: $decodedEvent');

  // Encode example
  final event = SseEvent(
    id: '42',
    event: 'greeting',
    data: 'Hello, SSE!\nWelcome to the event stream.',
  );
  final encodedSse = codec.encode(event);
  print('Encoded event:\n$encodedSse');
}
