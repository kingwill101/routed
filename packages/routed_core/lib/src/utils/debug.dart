import 'environment.dart';

void debugPrintWarning(String message) {
  if (const bool.fromEnvironment('dart.vm.product')) return;
  if (env['ROUTED_MODE'] == 'release') return;

  print('''
[Routed] WARNING: $message
To disable this warning set the ROUTED_MODE environment variable to "release"
''');
}
