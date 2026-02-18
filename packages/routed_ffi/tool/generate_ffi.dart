import 'dart:io';

import 'package:ffigen/ffigen.dart';

void main() {
  final packageRoot = Platform.script.resolve('../');
  FfiGenerator(
    headers: Headers(entryPoints: [packageRoot.resolve('native/bindings.h')]),
    output: Output(dartFile: packageRoot.resolve('lib/src/ffi.g.dart')),
    functions: Functions.includeSet({
      'routed_ffi_transport_version',
      'routed_ffi_start_proxy_server',
      'routed_ffi_stop_proxy_server',
    }),
    structs: Structs.includeSet({'RoutedFfiProxyConfig'}),
  ).generate();
}
