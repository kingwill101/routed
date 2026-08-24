import 'package:routed_core/src/utils/process_env.dart';

/// Prints a warning unless the application is running in release mode.
void debugPrintWarning(String message) {
  if (const bool.fromEnvironment('dart.vm.product')) return;
  if (readProcessEnvironment()['ROUTED_MODE'] == 'release') return;

  print('''
[Routed] WARNING: $message
To disable this warning set the ROUTED_MODE environment variable to "release"
''');
}
