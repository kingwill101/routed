part of 'server_boot.dart';

/// Encodes and writes length-prefixed bridge frames to a socket.
final class _BridgeSocketWriter {
  _BridgeSocketWriter(this._socket);

  final Socket _socket;

  /// Writes a full payload frame (`u32 length + payload`).
  void writeFrame(Uint8List payload) {
    if (payload.length > _maxBridgeFrameBytes) {
      throw FormatException(
        'bridge response frame too large: ${payload.length}',
      );
    }
    if (payload.isEmpty) {
      final prelude = Uint8List(4);
      _writeUint32BigEndian(prelude, 0, 0);
      _socket.add(prelude);
      return;
    }

    if (payload.length <= _coalescePayloadThresholdBytes) {
      final out = Uint8List(4 + payload.length);
      _writeUint32BigEndian(out, 0, payload.length);
      out.setRange(4, out.length, payload);
      _socket.add(out);
      return;
    }

    final prelude = Uint8List(4);
    _writeUint32BigEndian(prelude, 0, payload.length);
    _socket.add(prelude);
    _socket.add(payload);
  }

  /// Writes a response frame using prefix/body split encoding.
  void writeResponseFrame(BridgeResponseFrame response) {
    final body = response.bodyBytes;
    final prefix = response.encodePayloadPrefixWithoutBody();
    final payloadLength = prefix.length + body.length;
    if (payloadLength > _maxBridgeFrameBytes) {
      throw FormatException('bridge response frame too large: $payloadLength');
    }
    if (payloadLength <= _coalescePayloadThresholdBytes) {
      final out = Uint8List(4 + payloadLength);
      _writeUint32BigEndian(out, 0, payloadLength);
      out.setRange(4, 4 + prefix.length, prefix);
      if (body.isNotEmpty) {
        out.setRange(4 + prefix.length, out.length, body);
      }
      _socket.add(out);
      return;
    }

    final prelude = Uint8List(4 + prefix.length);
    _writeUint32BigEndian(prelude, 0, payloadLength);
    prelude.setRange(4, prelude.length, prefix);
    _socket.add(prelude);
    if (body.isNotEmpty) {
      _socket.add(body);
    }
  }

  /// Writes one chunk frame with [frameType] and [chunkBytes].
  void writeChunkFrame(int frameType, Uint8List chunkBytes) {
    final payloadLength = 6 + chunkBytes.length;
    if (payloadLength > _maxBridgeFrameBytes) {
      throw FormatException('bridge response frame too large: $payloadLength');
    }
    if (chunkBytes.length <= _coalescePayloadThresholdBytes) {
      final out = Uint8List(10 + chunkBytes.length);
      _writeUint32BigEndian(out, 0, payloadLength);
      out[4] = bridgeFrameProtocolVersion;
      out[5] = frameType & 0xff;
      _writeUint32BigEndian(out, 6, chunkBytes.length);
      if (chunkBytes.isNotEmpty) {
        out.setRange(10, out.length, chunkBytes);
      }
      _socket.add(out);
      return;
    }

    final prelude = Uint8List(10);
    _writeUint32BigEndian(prelude, 0, payloadLength);
    prelude[4] = bridgeFrameProtocolVersion;
    prelude[5] = frameType & 0xff;
    _writeUint32BigEndian(prelude, 6, chunkBytes.length);
    _socket.add(prelude);
    if (chunkBytes.isNotEmpty) {
      _socket.add(chunkBytes);
    }
  }

  /// Writes one chunk frame and flushes the socket immediately.
  Future<void> writeChunkFrameAndFlush(
    int frameType,
    Uint8List chunkBytes,
  ) async {
    writeChunkFrame(frameType, chunkBytes);
    await _socket.flush();
  }
}

@pragma('vm:prefer-inline')
/// Writes a big-endian u32 to [buffer] at [offset].
void _writeUint32BigEndian(Uint8List buffer, int offset, int value) {
  buffer[offset] = (value >> 24) & 0xff;
  buffer[offset + 1] = (value >> 16) & 0xff;
  buffer[offset + 2] = (value >> 8) & 0xff;
  buffer[offset + 3] = value & 0xff;
}

@pragma('vm:prefer-inline')
/// Reads a big-endian u32 from [buffer] at [offset].
int _readUint32BigEndian(Uint8List buffer, int offset) {
  return (buffer[offset] << 24) |
      (buffer[offset + 1] << 16) |
      (buffer[offset + 2] << 8) |
      buffer[offset + 3];
}

/// Incremental reader for bridge frames from a socket stream.
final class _SocketFrameReader {
  _SocketFrameReader(Socket socket)
    : _iterator = StreamIterator<Uint8List>(socket);

  final StreamIterator<Uint8List> _iterator;
  final ListQueue<Uint8List> _chunks = ListQueue<Uint8List>();
  int _chunkOffset = 0;
  int _availableBytes = 0;

  /// Reads one frame payload; returns `null` only for clean EOF before header.
  Future<Uint8List?> readFrame({Duration? timeout}) async {
    Future<Uint8List?> readOperation() async {
      final payloadLength = await _readUint32OrNull();
      if (payloadLength == null) {
        return null;
      }
      if (payloadLength > _maxBridgeFrameBytes) {
        throw FormatException('bridge frame too large: $payloadLength');
      }
      final payload = await _readExactOrNull(payloadLength);
      if (payload == null) {
        throw const FormatException('bridge stream ended before payload');
      }
      return payload;
    }

    if (timeout == null) {
      return readOperation();
    }
    return readOperation().timeout(timeout);
  }

  /// Cancels the underlying socket iterator.
  Future<void> cancel() => _iterator.cancel();

  /// Reads a frame length prefix; returns `null` only on clean EOF.
  Future<int?> _readUint32OrNull() async {
    final hasBytes = await _ensureAvailableOrNull(4);
    if (!hasBytes) {
      return null;
    }

    final first = _chunks.first;
    final start = _chunkOffset;
    final remainingInFirst = first.length - start;
    if (remainingInFirst >= 4) {
      final value = _readUint32BigEndian(first, start);
      _advanceFirstChunk(first, 4);
      return value;
    }

    final b0 = _consumeByte();
    final b1 = _consumeByte();
    final b2 = _consumeByte();
    final b3 = _consumeByte();
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
  }

  /// Reads exactly [count] bytes from buffered chunks.
  Future<Uint8List?> _readExactOrNull(int count) async {
    if (count == 0) {
      return Uint8List(0);
    }
    final hasBytes = await _ensureAvailableOrNull(count);
    if (!hasBytes) {
      return null;
    }

    // Fast path: satisfy the read directly from the current chunk view.
    if (_chunks.isNotEmpty) {
      final first = _chunks.first;
      final start = _chunkOffset;
      final remainingInFirst = first.length - start;
      if (remainingInFirst >= count) {
        final end = start + count;
        _advanceFirstChunk(first, count);
        return Uint8List.sublistView(first, start, end);
      }
    }

    final out = Uint8List(count);
    var written = 0;
    while (written < count) {
      final chunk = _chunks.first;
      final start = _chunkOffset;
      final remainingInChunk = chunk.length - start;
      final needed = count - written;
      final take = remainingInChunk < needed ? remainingInChunk : needed;
      out.setRange(written, written + take, chunk, start);
      written += take;
      _advanceFirstChunk(chunk, take);
    }
    return out;
  }

  @pragma('vm:prefer-inline')
  void _advanceFirstChunk(Uint8List chunk, int count) {
    _chunkOffset += count;
    _availableBytes -= count;
    if (_chunkOffset == chunk.length) {
      _chunks.removeFirst();
      _chunkOffset = 0;
    }
  }

  @pragma('vm:prefer-inline')
  int _consumeByte() {
    final chunk = _chunks.first;
    final value = chunk[_chunkOffset];
    _advanceFirstChunk(chunk, 1);
    return value;
  }

  /// Ensures at least [count] bytes are buffered, handling chunk boundaries.
  Future<bool> _ensureAvailableOrNull(int count) async {
    while (_availableBytes < count) {
      final hasNext = await _iterator.moveNext();
      if (!hasNext) {
        if (_availableBytes == 0) {
          return false;
        }
        throw const FormatException('bridge stream ended mid-frame');
      }
      final chunk = _iterator.current;
      if (chunk.isEmpty) {
        continue;
      }
      _chunks.addLast(chunk);
      _availableBytes += chunk.length;
    }
    return true;
  }
}
