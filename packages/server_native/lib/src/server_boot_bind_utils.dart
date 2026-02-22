part of 'server_boot.dart';

/// Whether this host can bind IPv6 loopback sockets.
final Future<bool> _supportsIPv6 = () async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}();

/// Whether this host can bind IPv4 loopback sockets.
final Future<bool> _supportsIPv4 = () async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}();

/// Returns the platform-specific `EADDRINUSE` error code.
int _addressInUseErrorCode() {
  if (Platform.isWindows) {
    return 10048;
  }
  if (Platform.isMacOS) {
    return 48;
  }
  return 98;
}

/// Returns whether [error] represents an address-in-use socket failure.
bool _isAddressInUseSocketException(Object error) {
  if (error is! SocketException) {
    return false;
  }
  return error.osError?.errorCode == _addressInUseErrorCode();
}

/// Returns whether [error] indicates a transient address-in-use bind failure.
///
/// Native proxy startup wraps socket bind errors in higher-level exceptions, so
/// this checks both raw [SocketException] values and wrapped error strings.
bool _isAddressInUseBindFailure(Object error) {
  if (_isAddressInUseSocketException(error)) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('address already in use') || text.contains('eaddrinuse');
}

/// Resolves the wildcard host for this machine (`::` when IPv6 is available).
Future<String> _anyHost() async {
  if (await _supportsIPv6) {
    return InternetAddress.anyIPv6.address;
  }
  return InternetAddress.anyIPv4.address;
}

/// Computes bind pairs for loopback multi-server startup.
///
/// When both IPv4 and IPv6 are available and `port == 0`, this reserves a
/// shared ephemeral port so both listeners use the same port number.
Future<List<NativeServerBind>> _loopbackBinds(int port) async {
  final supportsV4 = await _supportsIPv4;
  final supportsV6 = await _supportsIPv6;

  if (!supportsV4 && !supportsV6) {
    throw StateError(
      'Neither IPv4 nor IPv6 loopback sockets are available on this host',
    );
  }

  final bindPort = (port == 0 && supportsV4 && supportsV6)
      ? await _reserveSharedLoopbackPort()
      : port;

  if (!supportsV4) {
    return <NativeServerBind>[
      NativeServerBind(
        host: InternetAddress.loopbackIPv6.address,
        port: bindPort,
      ),
    ];
  }
  if (!supportsV6) {
    return <NativeServerBind>[
      NativeServerBind(
        host: InternetAddress.loopbackIPv4.address,
        port: bindPort,
      ),
    ];
  }
  return <NativeServerBind>[
    NativeServerBind(
      host: InternetAddress.loopbackIPv4.address,
      port: bindPort,
    ),
    NativeServerBind(
      host: InternetAddress.loopbackIPv6.address,
      port: bindPort,
    ),
  ];
}

/// Reserves an ephemeral loopback port that is available on both IPv4 and IPv6.
Future<int> _reserveSharedLoopbackPort({int retries = 5}) async {
  for (var attempt = 0; attempt <= retries; attempt++) {
    ServerSocket? v4Server;
    ServerSocket? v6Server;
    try {
      v4Server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final candidatePort = v4Server.port;
      v6Server = await ServerSocket.bind(
        InternetAddress.loopbackIPv6,
        candidatePort,
      );
      return candidatePort;
    } on SocketException catch (error) {
      if (attempt == retries || !_isAddressInUseSocketException(error)) {
        rethrow;
      }
    } finally {
      if (v6Server != null) {
        await v6Server.close();
      }
      if (v4Server != null) {
        await v4Server.close();
      }
    }
  }
  throw StateError('unreachable');
}

/// Normalizes a bind host input into a non-empty string address.
String _normalizeBindHost(Object value, String name) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty');
    }
    return trimmed;
  }
  if (value is InternetAddress) {
    return value.address;
  }
  throw ArgumentError.value(
    value,
    name,
    '$name must be a String or InternetAddress',
  );
}
