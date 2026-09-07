import 'package:artisanal/args.dart';

/// Writes command output through Artisanal's console abstraction on VM hosts.
void writeRoutedCommandLine(Command<void> command, String message) {
  command.line(message);
}
