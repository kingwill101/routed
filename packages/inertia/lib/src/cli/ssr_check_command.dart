library;

import 'package:artisanal/args.dart';
import 'package:artisanal/artisanal.dart';

import '../ssr/ssr_server.dart';
import 'ssr_utils.dart';

/// Implements the `inertia ssr:check` command.
///
/// ```dart
/// final exitCode = await InertiaSsrCheckCommand().run();
/// ```
///
/// Checks whether the SSR server is healthy.
class InertiaSsrCheckCommand extends Command<int> {
  /// Creates the `ssr:check` command.
  InertiaSsrCheckCommand() {
    argParser
      ..addOption(
        'url',
        defaultsTo: 'http://127.0.0.1:13714',
        help: 'SSR server base URL (without /render).',
      )
      ..addOption('health', help: 'Override the health endpoint URL.');
  }

  @override
  /// The command name.
  String get name => 'ssr:check';

  @override
  /// The command description.
  String get description => 'Check the Inertia SSR server health.';

  @override
  /// Runs the command and returns an exit code.
  Future<int> run() async {
    final io = this.io;
    final url = argResults?['url'] as String? ?? 'http://127.0.0.1:13714';
    final health = argResults?['health'] as String?;
    final baseUri = normalizeSsrBase(url);
    io.title('Checking Inertia SSR');
    io.twoColumnDetail('URL', baseUri.toString());

    try {
      final healthy = await checkSsrServer(
        endpoint: baseUri,
        healthEndpoint: health == null ? null : Uri.parse(health),
      );
      if (healthy) {
        io.success('Inertia SSR server is running.');
        return 0;
      }

      io.error('Inertia SSR server is not running.');
      return 1;
    } on UnsupportedError {
      io.error('The SSR gateway does not support health checks.');
      return 1;
    }
  }
}
