import 'dart:async';

import 'package:routed_core/routed_core.dart';

import 'node_views.dart';

/// [ResponseAdapter] backed by a Node.js [NodeServerResponseView].
final class NodeResponseAdapter implements ResponseAdapter {
  /// Creates an adapter over a Node server response.
  NodeResponseAdapter(this.outgoing);

  /// Underlying Node response view.
  final NodeServerResponseView outgoing;

  int _statusCode = 200;
  final Map<String, List<String>> _headers = {};
  bool _headersSent = false;
  bool _closed = false;

  @override
  int get statusCode => _statusCode;

  @override
  set statusCode(int value) {
    if (_headersSent) return;
    _statusCode = value;
  }

  @override
  void setHeader(String name, String value) {
    if (_headersSent) return;
    _headers[name] = [value];
  }

  @override
  void addHeader(String name, String value) {
    if (_headersSent) return;
    _headers.putIfAbsent(name, () => []).add(value);
  }

  void _ensureHeadersSent() {
    if (_headersSent) return;
    final flat = <String, Object>{};
    _headers.forEach((name, values) {
      if (name.toLowerCase() == 'set-cookie') {
        // Node accepts an array for set-cookie.
        flat[name] = values;
      } else if (values.length == 1) {
        flat[name] = values.first;
      } else {
        flat[name] = values.join(', ');
      }
    });
    outgoing.writeHead(_statusCode, flat);
    _headersSent = true;
  }

  @override
  void write(List<int> bytes) {
    if (_closed) {
      throw StateError('Cannot write to a closed Node response');
    }
    _ensureHeadersSent();
    if (bytes.isNotEmpty) {
      outgoing.write(bytes);
    }
  }

  @override
  Future<void> flush() async {
    // Node streams flush opportunistically; nothing to do.
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ensureHeadersSent();
    if (!outgoing.finished) {
      outgoing.end();
    }
  }
}
