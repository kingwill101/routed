import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  await _refreshNativeBindings(packageRoot);

  FfiGenerator(
    headers: Headers(entryPoints: [packageRoot.resolve('native/bindings.h')]),
    output: Output(dartFile: packageRoot.resolve('lib/src/ffi.g.dart')),
    functions: Functions.includeSet({
      'server_native_transport_version',
      'server_native_start_proxy_server',
      'server_native_stop_proxy_server',
      'server_native_push_direct_response_frame',
      'server_native_complete_direct_request',
      'server_native_poll_direct_request_frame',
      'server_native_free_direct_request_payload',
    }),
    structs: Structs.includeSet({'ServerNativeProxyConfig'}),
  ).generate();
}

Future<void> _refreshNativeBindings(Uri packageRoot) async {
  final nativeDir = Directory.fromUri(packageRoot.resolve('native/'));
  final result = await Process.run(
    'cargo',
    const <String>['build', '--quiet'],
    workingDirectory: nativeDir.path,
    environment: <String, String>{
      ...Platform.environment,
      'SERVER_NATIVE_GENERATE_BINDINGS': '1',
    },
    runInShell: Platform.isWindows,
  );

  if (result.exitCode != 0) {
    throw ProcessException(
      'cargo',
      const <String>['build', '--quiet'],
      [
        if (result.stdout is String && (result.stdout as String).isNotEmpty)
          result.stdout as String,
        if (result.stderr is String && (result.stderr as String).isNotEmpty)
          result.stderr as String,
      ].join('\n'),
      result.exitCode,
    );
  }
}
