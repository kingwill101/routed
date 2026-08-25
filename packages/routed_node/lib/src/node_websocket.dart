import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:routed_core/routed_core.dart';

import 'node_views.dart';

/// Native handshake information for a Node upgrade.
final class NodeWebSocketUpgradeResponse {
  /// Creates a NodeWebSocketUpgradeResponse value.
  const NodeWebSocketUpgradeResponse({
    required this.socket,
    required this.key,
    this.protocol,
  });

  /// Upgraded Node socket that will carry the WebSocket frames.
  final NodeWebSocketSocketView socket;

  /// Client handshake key used to derive [acceptKey].
  final String key;

  /// Negotiated subprotocol, when one was selected.
  final String? protocol;

  /// Base64-encoded `Sec-WebSocket-Accept` handshake value.
  String get acceptKey =>
      base64.encode(sha1.convert(utf8.encode('$key$_webSocketGuid')).bytes);

  /// Raw HTTP 101 handshake bytes for the upgraded connection.
  List<int> get handshake => utf8.encode(
    'HTTP/1.1 101 Switching Protocols\r\n'
    'Upgrade: websocket\r\n'
    'Connection: Upgrade\r\n'
    'Sec-WebSocket-Accept: $acceptKey\r\n'
    '${protocol == null ? '' : 'Sec-WebSocket-Protocol: $protocol\r\n'}\r\n',
  );
}

/// Result of accepting a Node WebSocket upgrade.
final class NodeWebSocketAcceptance {
  /// Creates a NodeWebSocketAcceptance value.
  const NodeWebSocketAcceptance({required this.socket, required this.response});

  /// WebSocket implementation backed by the accepted Node socket.
  final NodeRoutedWebSocket socket;

  /// HTTP handshake response that must be written to the socket.
  final NodeWebSocketUpgradeResponse response;
}

/// WebSocket implementation for a raw Node upgrade socket.
final class NodeRoutedWebSocket implements RoutedWebSocket {
  /// Starts decoding WebSocket frames from a Node upgrade socket.
  NodeRoutedWebSocket({required this.socket, List<int> head = const []}) {
    _subscription = socket.incoming.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
    if (head.isNotEmpty) _onData(head);
  }

  /// Raw Node socket carrying the WebSocket frames.
  final NodeWebSocketSocketView socket;
  final StreamController<Object?> _messages = StreamController<Object?>();
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final BytesBuilder _fragment = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> _subscription;
  bool _closed = false;
  bool _closeSent = false;
  int? _fragmentOpcode;

  @override
  Stream<Object?> get stream => _messages.stream;

  @override
  int? get closeCode => null;

  @override
  void add(Object? data) {
    if (_closed || _closeSent) throw StateError('WebSocket is closed.');
    final payload = data is List<int>
        ? data
        : Uint8List.fromList(utf8.encode(data?.toString() ?? ''));
    unawaited(socket.write(_frame(data is List<int> ? 2 : 1, payload)));
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closeSent) return;
    _closeSent = true;
    final payload = <int>[];
    if (code != null) {
      payload
        ..add((code >> 8) & 0xff)
        ..add(code & 0xff)
        ..addAll(utf8.encode(reason ?? ''));
    }
    await socket.write(_frame(8, payload));
    await socket.end();
    _finish();
  }

  void _onData(List<int> chunk) {
    if (_closed || chunk.isEmpty) return;
    _buffer.add(chunk);
    final bytes = _buffer.takeBytes();
    var offset = 0;
    while (offset + 2 <= bytes.length) {
      final first = bytes[offset];
      final second = bytes[offset + 1];
      final fin = first & 0x80 != 0;
      final opcode = first & 0x0f;
      final masked = second & 0x80 != 0;
      var length = second & 0x7f;
      var cursor = offset + 2;
      if (length == 126) {
        if (cursor + 2 > bytes.length) break;
        length = (bytes[cursor] << 8) | bytes[cursor + 1];
        cursor += 2;
      } else if (length == 127) {
        if (cursor + 8 > bytes.length) break;
        length = 0;
        for (var i = 0; i < 8; i++) {
          length = (length << 8) | bytes[cursor + i];
        }
        cursor += 8;
      }
      if (!masked) {
        _protocolError();
        return;
      }
      if (cursor + 4 + length > bytes.length) break;
      final mask = bytes.sublist(cursor, cursor + 4);
      cursor += 4;
      final payload = Uint8List(length);
      for (var i = 0; i < length; i++) {
        payload[i] = bytes[cursor + i] ^ mask[i % 4];
      }
      offset = cursor + length;
      if (!_handleFrame(fin, opcode, payload)) return;
    }
    if (offset < bytes.length) _buffer.add(bytes.sublist(offset));
  }

  bool _handleFrame(bool fin, int opcode, Uint8List payload) {
    switch (opcode) {
      case 0:
        if (_fragmentOpcode == null) return _protocolError();
        _fragment.add(payload);
        if (!fin) return true;
        final type = _fragmentOpcode!;
        _fragmentOpcode = null;
        return _emit(type, _fragment.takeBytes());
      case 1:
      case 2:
        if (!fin) {
          _fragmentOpcode = opcode;
          _fragment.add(payload);
          return true;
        }
        return _emit(opcode, payload);
      case 8:
        if (!_closeSent) unawaited(close());
        _finish();
        return true;
      case 9:
        unawaited(socket.write(_frame(10, payload)));
        return true;
      case 10:
        return true;
      default:
        return _protocolError();
    }
  }

  bool _emit(int opcode, List<int> payload) {
    if (opcode == 1) {
      _messages.add(utf8.decode(payload));
    } else if (opcode == 2) {
      _messages.add(Uint8List.fromList(payload));
    } else {
      return _protocolError();
    }
    return true;
  }

  bool _protocolError() {
    unawaited(close(1002, 'WebSocket protocol error'));
    return false;
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_closed) _messages.addError(error, stackTrace);
    _finish();
  }

  void _onDone() => _finish();

  void _finish() {
    if (_closed) return;
    _closed = true;
    if (!_messages.isClosed) unawaited(_messages.close());
    unawaited(_subscription.cancel());
  }

  Uint8List _frame(int opcode, List<int> payload) {
    final out = BytesBuilder(copy: false)..addByte(0x80 | opcode);
    if (payload.length < 126) {
      out.addByte(payload.length);
    } else if (payload.length <= 0xffff) {
      out
        ..addByte(126)
        ..addByte(payload.length >> 8)
        ..addByte(payload.length & 0xff);
    } else {
      out.addByte(127);
      for (var shift = 56; shift >= 0; shift -= 8) {
        out.addByte((payload.length >> shift) & 0xff);
      }
    }
    out.add(payload);
    return out.takeBytes();
  }
}

const _webSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
