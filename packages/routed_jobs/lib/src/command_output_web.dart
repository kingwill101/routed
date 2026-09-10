import 'package:artisanal/args.dart';

/// Writes command output using the JS-safe fallback on web hosts.
void writeRoutedCommandLine(Command<void> _, String message) {
  // Artisanal's web Command intentionally omits the VM console helper.
  // ignore: avoid_print
  print(message);
}
