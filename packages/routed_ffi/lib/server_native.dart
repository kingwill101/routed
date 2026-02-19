library;

/// Native Rust-backed HTTP server APIs for Dart.
///
/// This library is the public entrypoint for `server_native`.
/// It exposes:
///
/// - `HttpServer`-style APIs via [NativeHttpServer].
/// - callback-style APIs via [serveNativeHttp] and [serveSecureNativeHttp].
/// - direct request/response callback APIs via [serveNativeDirect] and
///   [serveSecureNativeDirect].
/// - multi-bind helpers via [NativeMultiServer] and [serveNativeMulti].
///
/// The API surface is designed so you can start from a familiar
/// `dart:io HttpServer` model and selectively move to lower-overhead
/// callback paths.
///
/// {@template server_native_quick_start}
/// ## Quick Start (`HttpServer` style)
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:server_native/server_native.dart';
///
/// Future<void> main() async {
///   final server = await NativeHttpServer.bind('127.0.0.1', 8080);
///
///   await for (final request in server) {
///     request.response
///       ..statusCode = HttpStatus.ok
///       ..headers.contentType = ContentType.text
///       ..write('ok');
///     await request.response.close();
///   }
/// }
/// ```
/// {@endtemplate}
///
/// {@template server_native_http_callback_example}
/// ## Callback API (`HttpRequest`)
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:server_native/server_native.dart';
///
/// Future<void> main() async {
///   await serveNativeHttp((request) async {
///     request.response
///       ..statusCode = HttpStatus.ok
///       ..headers.contentType = ContentType.text
///       ..write('hello');
///     await request.response.close();
///   }, host: '127.0.0.1', port: 8080);
/// }
/// ```
/// {@endtemplate}
///
/// {@template server_native_direct_callback_example}
/// ## Direct Callback API (`NativeDirectRequest`)
///
/// ```dart
/// import 'dart:io';
/// import 'dart:typed_data';
///
/// import 'package:server_native/server_native.dart';
///
/// Future<void> main() async {
///   await serveNativeDirect((request) async {
///     return NativeDirectResponse.bytes(
///       status: HttpStatus.ok,
///       headers: const <MapEntry<String, String>>[
///         MapEntry(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8'),
///       ],
///       bodyBytes: Uint8List.fromList('ok'.codeUnits),
///     );
///   }, host: '127.0.0.1', port: 8080, nativeDirect: true);
/// }
/// ```
/// {@endtemplate}
///
/// {@template server_native_tls_example}
/// ## TLS / HTTPS
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:server_native/server_native.dart';
///
/// Future<void> main() async {
///   final server = await NativeHttpServer.bindSecure(
///     '127.0.0.1',
///     8443,
///     certificatePath: 'cert.pem',
///     keyPath: 'key.pem',
///     http3: true,
///   );
///
///   await for (final request in server) {
///     request.response
///       ..statusCode = HttpStatus.ok
///       ..headers.contentType = ContentType.text
///       ..write('secure');
///     await request.response.close();
///   }
/// }
/// ```
/// {@endtemplate}
///
/// {@template server_native_graceful_shutdown_example}
/// ## Graceful shutdown
///
/// ```dart
/// import 'dart:async';
/// import 'dart:io';
///
/// import 'package:server_native/server_native.dart';
///
/// Future<void> main() async {
///   final shutdown = Completer<void>();
///   final serveFuture = serveNativeHttp((request) async {
///     request.response
///       ..statusCode = HttpStatus.ok
///       ..write('bye');
///     await request.response.close();
///   }, shutdownSignal: shutdown.future);
///
///   // Complete when your app receives a termination signal.
///   shutdown.complete();
///   await serveFuture;
/// }
/// ```
/// {@endtemplate}

/// Core server boot APIs and server abstractions.
///
/// Includes:
///
/// - [NativeHttpServer] for stream-based `HttpServer` handling.
/// - [NativeMultiServer] and [NativeServerBind] for multi-bind boot helpers.
/// - [serveNativeHttp]/[serveSecureNativeHttp] for callback-style request handling.
/// - [serveNativeDirect]/[serveSecureNativeDirect] for direct low-overhead handlers.
///
/// {@macro server_native_quick_start}
/// {@macro server_native_http_callback_example}
/// {@macro server_native_direct_callback_example}
/// {@macro server_native_tls_example}
/// {@macro server_native_graceful_shutdown_example}
export 'src/server_boot.dart'
    show
        NativeHttpServer,
        NativeMultiServer,
        NativeServerBind,
        NativeDirectHandler,
        NativeDirectRequest,
        NativeDirectResponse,
        serveNative,
        serveNativeMulti,
        serveNativeHttp,
        serveNativeDirect,
        serveSecureNative,
        serveSecureNativeMulti,
        serveSecureNativeHttp,
        serveSecureNativeDirect;

/// ABI version helper for the linked native transport asset.
///
/// Useful for compatibility checks in diagnostics or test assertions.
export 'src/native/server_native_transport.dart' show transportAbiVersion;
