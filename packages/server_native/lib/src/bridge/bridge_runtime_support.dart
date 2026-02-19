part of 'bridge_runtime.dart';

/// Basic connection info exposed by bridge-backed request/response adapters.
final class BridgeConnectionInfo implements HttpConnectionInfo {
  const BridgeConnectionInfo();

  @override
  int get localPort => 0;

  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;

  @override
  int get remotePort => 0;
}

/// In-memory `HttpSession` implementation used by bridge-backed requests.
final class BridgeSession extends MapBase<dynamic, dynamic>
    implements HttpSession {
  @override
  String id = 'bridge';

  @override
  bool isNew = false;

  Map<String, dynamic>? _data;

  Duration timeout = const Duration(minutes: 20);

  @override
  void destroy() => _data?.clear();

  @override
  set onTimeout(void Function() callback) {}

  @override
  dynamic operator [](Object? key) => key is String ? (_data?[key]) : null;

  @override
  void clear() => _data?.clear();

  @override
  Iterable<dynamic> get keys => _data?.keys ?? const <String>[];

  @override
  void operator []=(Object? key, dynamic value) {
    if (key is! String) {
      throw ArgumentError('Session keys must be strings');
    }
    (_data ??= <String, dynamic>{})[key] = value;
  }

  @override
  dynamic remove(Object? key) => key is String ? _data?.remove(key) : null;
}
