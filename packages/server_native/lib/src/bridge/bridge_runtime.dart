import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Bridge runtime primitives for routing requests between Rust transport
/// and Dart request handlers.
///
/// {@template server_native_bridge_protocol_overview}
/// Frames are encoded as length-prefixed binary payloads:
/// `version(1) + frameType(1) + fields...`.
/// Strings and byte fields are encoded as `u32 length + bytes` using UTF-8
/// for text.
/// {@endtemplate}
///
/// {@template server_native_bridge_request_example}
/// Example:
/// ```dart
/// final request = BridgeRequestFrame(
///   method: 'GET',
///   scheme: 'http',
///   authority: '127.0.0.1:8080',
///   path: '/health',
///   query: '',
///   protocol: '1.1',
///   headers: const <MapEntry<String, String>>[
///     MapEntry('accept', 'application/json'),
///   ],
///   bodyBytes: Uint8List(0),
/// );
///
/// final decoded = BridgeRequestFrame.decodePayload(request.encodePayload());
/// ```
/// {@endtemplate}
///
/// {@template server_native_bridge_response_example}
/// Example:
/// ```dart
/// final response = BridgeResponseFrame(
///   status: 200,
///   headers: const <MapEntry<String, String>>[
///     MapEntry('content-type', 'application/json'),
///   ],
///   bodyBytes: Uint8List.fromList('{"ok":true}'.codeUnits),
/// );
///
/// final decoded = BridgeResponseFrame.decodePayload(response.encodePayload());
/// ```
/// {@endtemplate}
///
/// {@template server_native_bridge_runtime_example}
/// Example:
/// ```dart
/// final runtime = BridgeHttpRuntime((request) async {
///   request.response.statusCode = HttpStatus.ok;
///   request.response.headers.contentType = ContentType.text;
///   request.response.write('hello');
///   await request.response.close();
/// });
/// final response = await runtime.handleFrame(requestFrame);
/// ```
/// {@endtemplate}
part 'bridge_runtime_codec.dart';
part 'bridge_runtime_runtime.dart';
part 'bridge_runtime_request.dart';
part 'bridge_runtime_response.dart';
part 'bridge_runtime_support.dart';
