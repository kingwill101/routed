import 'package:routed/routed.dart';

/// Boots a Routed [engine] using the `dart:io` HTTP server transport.
Future<void> serveIo(
  Engine engine, {
  String host = '127.0.0.1',
  int? port,
  bool echo = true,
}) {
  return engine.serve(host: host, port: port, echo: echo);
}

/// Boots a Routed [engine] using the `dart:io` HTTPS server transport.
Future<void> serveSecureIo(
  Engine engine, {
  String address = 'localhost',
  int port = 443,
  String? certificatePath,
  String? keyPath,
  String? certificatePassword,
  bool? v6Only,
  bool? requestClientCertificate,
  bool? shared,
}) {
  return engine.serveSecure(
    address: address,
    port: port,
    certificatePath: certificatePath,
    keyPath: keyPath,
    certificatePassword: certificatePassword,
    v6Only: v6Only,
    requestClientCertificate: requestClientCertificate,
    shared: shared,
  );
}
