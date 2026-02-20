part of 'bridge_runtime.dart';

/// Socket pair used to bridge upgraded protocol bytes over FFI frames.
final class BridgeDetachedSocket {
  BridgeDetachedSocket({
    required this.applicationSocket,
    required this.bridgeSocket,
  });

  /// Socket handed to Dart upgrade APIs (`WebSocketTransformer.upgrade`).
  final Socket applicationSocket;

  /// Peer socket retained by the bridge runtime for Rust tunnel forwarding.
  final Socket bridgeSocket;

  Uint8List? _prefetchedTunnelBytes;
  StreamIterator<Uint8List>? _bridgeIterator;

  /// Stores bytes that were already read while parsing detached prefaces.
  ///
  /// These bytes are emitted first when the detached tunnel loop starts.
  void stashPrefetchedTunnelBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return;
    }
    final existing = _prefetchedTunnelBytes;
    if (existing == null || existing.isEmpty) {
      _prefetchedTunnelBytes = bytes;
      return;
    }
    final merged = Uint8List(existing.length + bytes.length);
    merged.setRange(0, existing.length, existing);
    merged.setRange(existing.length, merged.length, bytes);
    _prefetchedTunnelBytes = merged;
  }

  /// Returns and clears prefetched tunnel bytes.
  Uint8List? takePrefetchedTunnelBytes() {
    final bytes = _prefetchedTunnelBytes;
    _prefetchedTunnelBytes = null;
    return bytes;
  }

  /// Returns a shared iterator for detached bridge reads.
  StreamIterator<Uint8List> bridgeIterator() {
    return _bridgeIterator ??= StreamIterator(bridgeSocket);
  }

  /// Closes both ends of the detached socket pair, ignoring close races.
  Future<void> close() async {
    final iterator = _bridgeIterator;
    _bridgeIterator = null;
    if (iterator != null) {
      try {
        await iterator.cancel();
      } catch (_) {}
    }
    try {
      await applicationSocket.close();
    } catch (_) {}
    try {
      await bridgeSocket.close();
    } catch (_) {}
  }
}

/// Creates a loopback socket pair used by `HttpResponse.detachSocket`.
Future<BridgeDetachedSocket> _createDetachedSocketPair() async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final bridgeSocketFuture = listener.first;
    final applicationSocketFuture = Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );

    final bridgeSocket = await bridgeSocketFuture;
    final applicationSocket = await applicationSocketFuture;
    try {
      bridgeSocket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    try {
      applicationSocket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    return BridgeDetachedSocket(
      applicationSocket: applicationSocket,
      bridgeSocket: bridgeSocket,
    );
  } finally {
    await listener.close();
  }
}

const Duration _manualDetachedPrefaceTimeout = Duration(seconds: 5);
const int _manualDetachedPrefaceMaxBytes = 64 * 1024;

/// Parsed detached HTTP response preface (status + headers + trailing bytes).
final class _DetachedHttpResponsePreface {
  _DetachedHttpResponsePreface({
    required this.status,
    required this.headerNames,
    required this.headerValues,
    required this.trailingBytes,
  });

  final int status;
  final List<String> headerNames;
  final List<String> headerValues;
  final Uint8List trailingBytes;
}

/// Reads and parses one detached HTTP response preface from [detached].
///
/// Used when callers invoke `detachSocket(writeHeaders: false)` and write a
/// raw HTTP handshake/status preface manually.
Future<_DetachedHttpResponsePreface> _readDetachedHttpResponsePreface(
  BridgeDetachedSocket detached,
) async {
  final iterator = detached.bridgeIterator();
  final builder = BytesBuilder(copy: false);
  int? prefaceEnd;

  while (true) {
    final hasChunk = await iterator.moveNext().timeout(
      _manualDetachedPrefaceTimeout,
    );
    if (!hasChunk) {
      throw StateError(
        'detached socket closed before HTTP preface was written',
      );
    }

    final chunk = iterator.current;
    if (chunk.isNotEmpty) {
      builder.add(chunk);
    }

    final bytes = builder.toBytes();
    if (bytes.length > _manualDetachedPrefaceMaxBytes) {
      throw FormatException(
        'detached HTTP preface exceeds $_manualDetachedPrefaceMaxBytes bytes',
      );
    }

    prefaceEnd = _indexOfHttpPrefaceTerminator(bytes);
    if (prefaceEnd != null) {
      final prefaceBytes = bytes.sublist(0, prefaceEnd);
      final trailing = bytes.sublist(prefaceEnd + 4);
      final decoded = ascii.decode(prefaceBytes, allowInvalid: false);
      final parsed = _parseDetachedHttpResponsePreface(decoded);
      return _DetachedHttpResponsePreface(
        status: parsed.status,
        headerNames: parsed.headerNames,
        headerValues: parsed.headerValues,
        trailingBytes: Uint8List.fromList(trailing),
      );
    }
  }
}

int? _indexOfHttpPrefaceTerminator(Uint8List bytes) {
  final limit = bytes.length - 3;
  for (var i = 0; i < limit; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return i;
    }
  }
  return null;
}

final class _ParsedDetachedHttpPreface {
  _ParsedDetachedHttpPreface({
    required this.status,
    required this.headerNames,
    required this.headerValues,
  });

  final int status;
  final List<String> headerNames;
  final List<String> headerValues;
}

_ParsedDetachedHttpPreface _parseDetachedHttpResponsePreface(String preface) {
  final lines = preface.split('\r\n');
  if (lines.isEmpty || lines.first.isEmpty) {
    throw const FormatException(
      'detached HTTP preface is missing a status line',
    );
  }

  final statusLine = lines.first;
  final firstSpace = statusLine.indexOf(' ');
  if (firstSpace == -1 || firstSpace + 4 > statusLine.length) {
    throw FormatException('invalid detached HTTP status line: $statusLine');
  }
  final statusText = statusLine.substring(firstSpace + 1);
  final secondSpace = statusText.indexOf(' ');
  final codeText = secondSpace == -1
      ? statusText
      : statusText.substring(0, secondSpace);
  final status = int.tryParse(codeText);
  if (status == null || status < 100 || status > 999) {
    throw FormatException('invalid detached HTTP status code: $codeText');
  }

  final headerNames = <String>[];
  final headerValues = <String>[];
  for (final line in lines.skip(1)) {
    if (line.isEmpty) {
      continue;
    }
    final separator = line.indexOf(':');
    if (separator <= 0) {
      throw FormatException('invalid detached HTTP header line: $line');
    }
    final name = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    if (name.isEmpty) {
      throw FormatException('invalid detached HTTP header line: $line');
    }
    headerNames.add(name);
    headerValues.add(value);
  }

  return _ParsedDetachedHttpPreface(
    status: status,
    headerNames: headerNames,
    headerValues: headerValues,
  );
}
