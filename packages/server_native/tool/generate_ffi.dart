import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  await _refreshNativeBindings(packageRoot);

  FfiGenerator(
    headers: Headers(entryPoints: [packageRoot.resolve('native/bindings.h')]),
    output: Output(dartFile: packageRoot.resolve('lib/src/ffi.g.dart')),
    functions: Functions.includeSet({
      'routed_ffi_transport_version',
      'routed_ffi_start_proxy_server',
      'routed_ffi_stop_proxy_server',
      'routed_ffi_push_direct_response_frame',
      'routed_ffi_complete_direct_request',
    }),
    structs: Structs.includeSet({'RoutedFfiProxyConfig'}),
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
      'ROUTED_FFI_GENERATE_BINDINGS': '1',
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
