part of 'bridge_runtime.dart';

/// Basic connection info exposed by bridge-backed request/response adapters.
final class BridgeConnectionInfo implements HttpConnectionInfo {
  const BridgeConnectionInfo({
    required this.remoteAddress,
    required this.remotePort,
    required this.localPort,
  });

  factory BridgeConnectionInfo.fromRequestFrame(BridgeRequestFrame frame) {
    final hostHeader = _bridgeHeaderValue(frame, HttpHeaders.hostHeader);
    final authority = _splitBridgeAuthority(
      (hostHeader != null && hostHeader.isNotEmpty)
          ? hostHeader
          : frame.authority,
    );
    final remoteAddress = _inferRemoteAddress(authority.host);
    return BridgeConnectionInfo(
      remoteAddress: remoteAddress,
      remotePort: 0,
      localPort: authority.port ?? 0,
    );
  }

  @override
  final int localPort;

  @override
  final InternetAddress remoteAddress;

  @override
  final int remotePort;
}

InternetAddress _inferRemoteAddress(String host) {
  if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
    return InternetAddress.loopbackIPv4;
  }
  if (host == '::1' || host == '[::1]') {
    return InternetAddress.loopbackIPv6;
  }
  return InternetAddress.tryParse(host) ?? InternetAddress.loopbackIPv4;
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
