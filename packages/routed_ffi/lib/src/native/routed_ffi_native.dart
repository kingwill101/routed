import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:routed_ffi/src/ffi.g.dart';

const int bridgeBackendKindTcp = 0;
const int bridgeBackendKindUnix = 1;

/// Returns the ABI version for the linked Rust native asset.
int transportAbiVersion() => routed_ffi_transport_version();

/// Handle to a running native Rust proxy transport server.
final class NativeProxyServer {
  NativeProxyServer._(this._handle, this.port);

  final ffi.Pointer<ProxyServerHandle> _handle;

  /// Public port exposed by the Rust transport server.
  final int port;

  bool _closed = false;

  /// Starts a Rust proxy server that forwards requests to a local Dart backend.
  static NativeProxyServer start({
    required String host,
    required int port,
    required String backendHost,
    required int backendPort,
    int backendKind = bridgeBackendKindTcp,
    String? backendPath,
    bool enableHttp3 = false,
    String? tlsCertPath,
    String? tlsKeyPath,
    int benchmarkMode = 0,
  }) {
    if (backendKind < 0 || backendKind > 255) {
      throw ArgumentError.value(
        backendKind,
        'backendKind',
        'backendKind must be between 0 and 255',
      );
    }
    if (backendKind == bridgeBackendKindUnix &&
        (backendPath == null || backendPath.isEmpty)) {
      throw ArgumentError.value(
        backendPath,
        'backendPath',
        'backendPath is required when backendKind is Unix',
      );
    }
    if (benchmarkMode < 0 || benchmarkMode > 255) {
      throw ArgumentError.value(
        benchmarkMode,
        'benchmarkMode',
        'benchmarkMode must be between 0 and 255',
      );
    }

    final configPtr = calloc<RoutedFfiProxyConfig>();
    final outPortPtr = calloc<ffi.Uint16>();
    final hostPtr = host.toNativeUtf8();
    final backendHostPtr = backendHost.toNativeUtf8();
    final backendPathPtr = backendPath?.toNativeUtf8();
    final tlsCertPathPtr = tlsCertPath?.toNativeUtf8();
    final tlsKeyPathPtr = tlsKeyPath?.toNativeUtf8();

    try {
      configPtr.ref
        ..host = hostPtr.cast<ffi.Char>()
        ..port = port
        ..backend_host = backendHostPtr.cast<ffi.Char>()
        ..backend_port = backendPort
        ..backend_kind = backendKind
        ..backend_path = (backendPathPtr ?? ffi.nullptr).cast<ffi.Char>()
        ..http3 = enableHttp3 ? 1 : 0
        ..tls_cert_path = (tlsCertPathPtr ?? ffi.nullptr).cast<ffi.Char>()
        ..tls_key_path = (tlsKeyPathPtr ?? ffi.nullptr).cast<ffi.Char>()
        ..benchmark_mode = benchmarkMode;

      final handle = routed_ffi_start_proxy_server(configPtr, outPortPtr);
      if (handle == ffi.nullptr) {
        throw StateError(
          'Failed to start routed_ffi native proxy server for $host:$port',
        );
      }

      return NativeProxyServer._(handle, outPortPtr.value);
    } finally {
      if (tlsCertPathPtr != null) {
        calloc.free(tlsCertPathPtr);
      }
      if (backendPathPtr != null) {
        calloc.free(backendPathPtr);
      }
      if (tlsKeyPathPtr != null) {
        calloc.free(tlsKeyPathPtr);
      }
      calloc.free(hostPtr);
      calloc.free(backendHostPtr);
      calloc.free(outPortPtr);
      calloc.free(configPtr);
    }
  }

  /// Stops the native proxy server.
  void close() {
    if (_closed) return;
    _closed = true;
    routed_ffi_stop_proxy_server(_handle);
  }
}
