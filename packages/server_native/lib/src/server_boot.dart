import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_native/src/bridge/bridge_runtime.dart';
import 'package:server_native/src/native/server_native_transport.dart';

part 'server_boot_api.dart';
part 'server_boot_api_direct.dart';
part 'server_boot_api_multi.dart';
part 'server_boot_serve.dart';
part 'server_boot_http_server.dart';
part 'server_boot_http_server_bootstrap.dart';
part 'server_boot_http_server_policy.dart';
part 'server_boot_http_session.dart';
part 'server_boot_proxy.dart';
part 'server_boot_proxy_bridge.dart';
part 'server_boot_proxy_direct.dart';
part 'server_boot_bind_utils.dart';
part 'server_boot_direct.dart';
part 'server_boot_direct_payload.dart';
part 'server_boot_direct_io.dart';

/// Maximum accepted bridge frame payload size.
const int _maxBridgeFrameBytes = 64 * 1024 * 1024;

/// Maximum accepted request/response body size bridged through Dart.
const int _maxBridgeBodyBytes = 32 * 1024 * 1024;

/// Payload size threshold where writes are coalesced into one socket add.
const int _coalescePayloadThresholdBytes = 4 * 1024;
const int _bridgeRequestFrameTypeLegacy = 1;
const int _bridgeRequestFrameTypeTokenized = 11;
const int _bridgeHeaderNameLiteralToken = 0xffff;
const Utf8Decoder _directStrictUtf8Decoder = Utf8Decoder(allowMalformed: false);
const List<String> _directBridgeHeaderNameTable = <String>[
  'host',
  'connection',
  'user-agent',
  'accept',
  'accept-encoding',
  'accept-language',
  'content-type',
  'content-length',
  'transfer-encoding',
  'cookie',
  'set-cookie',
  'cache-control',
  'pragma',
  'upgrade',
  'authorization',
  'origin',
  'referer',
  'location',
  'server',
  'date',
  'x-forwarded-for',
  'x-forwarded-proto',
  'x-forwarded-host',
  'x-forwarded-port',
  'x-request-id',
  'sec-websocket-key',
  'sec-websocket-version',
  'sec-websocket-protocol',
  'sec-websocket-extensions',
];

/// {@template server_native_serve_handler_example}
/// Example:
/// ```dart
/// await serveNative(
///   (request) async {
///     request.response
///       ..statusCode = HttpStatus.ok
///       ..headers.contentType = ContentType.text
///       ..write('ok');
///     await request.response.close();
///   },
///   host: InternetAddress.loopbackIPv4,
///   port: 8080,
/// );
/// ```
/// {@endtemplate}
///
/// {@template server_native_serve_http_handler_example}
/// Example:
/// ```dart
/// await serveNativeHttp((request) async {
///   request.response
///     ..statusCode = HttpStatus.ok
///     ..headers.contentType = ContentType.text
///     ..write('ok');
///   await request.response.close();
/// }, host: InternetAddress.loopbackIPv4, port: 8080);
/// ```
/// {@endtemplate}

@pragma('vm:prefer-inline')
/// Returns the compact bridge token for a known lowercase header name.
int? _directHeaderLookupToken(String name) {
  switch (name) {
    case 'host':
      return 0;
    case 'connection':
      return 1;
    case 'user-agent':
      return 2;
    case 'accept':
      return 3;
    case 'accept-encoding':
      return 4;
    case 'accept-language':
      return 5;
    case 'content-type':
      return 6;
    case 'content-length':
      return 7;
    case 'transfer-encoding':
      return 8;
    case 'cookie':
      return 9;
    case 'set-cookie':
      return 10;
    case 'cache-control':
      return 11;
    case 'pragma':
      return 12;
    case 'upgrade':
      return 13;
    case 'authorization':
      return 14;
    case 'origin':
      return 15;
    case 'referer':
      return 16;
    case 'location':
      return 17;
    case 'server':
      return 18;
    case 'date':
      return 19;
    case 'x-forwarded-for':
      return 20;
    case 'x-forwarded-proto':
      return 21;
    case 'x-forwarded-host':
      return 22;
    case 'x-forwarded-port':
      return 23;
    case 'x-request-id':
      return 24;
    case 'sec-websocket-key':
      return 25;
    case 'sec-websocket-version':
      return 26;
    case 'sec-websocket-protocol':
      return 27;
    case 'sec-websocket-extensions':
      return 28;
  }
  return null;
}

/// Bridge backend binding details for the active runtime.
final class _BridgeBinding {
  _BridgeBinding({
    required this.server,
    required this.backendKind,
    required this.backendHost,
    required this.backendPort,
    required this.backendPath,
    required this.dispose,
  });

  final ServerSocket server;
  final int backendKind;
  final String backendHost;
  final int backendPort;
  final String? backendPath;
  final Future<void> Function() dispose;
}

/// Resolves [host] into an [InternetAddress], preserving already-parsed IPs.
Future<InternetAddress> _resolveInternetAddress(String host) async {
  final parsed = InternetAddress.tryParse(host);
  if (parsed != null) {
    return parsed;
  }
  final resolved = await InternetAddress.lookup(host);
  if (resolved.isEmpty) {
    throw StateError('Unable to resolve host "$host"');
  }
  return resolved.first;
}

/// Wrapper around either a decoded frame response or an encoded payload.
final class _BridgeHandleFrameResult {
  _BridgeHandleFrameResult.frame(BridgeResponseFrame frame)
    : _frame = frame,
      _encodedPayload = null;

  _BridgeHandleFrameResult.encoded(Uint8List payload)
    : _frame = null,
      _encodedPayload = payload;

  final BridgeResponseFrame? _frame;
  final Uint8List? _encodedPayload;

  BridgeResponseFrame get frame => _frame!;

  Uint8List? get encodedPayload => _encodedPayload;

  BridgeDetachedSocket? get detachedSocket => _frame?.detachedSocket;
}
