library;

import 'package:artisanal/args.dart';
import 'package:artisanal/artisanal.dart';

import '../ssr/ssr_server.dart';
import 'ssr_utils.dart';

/// Implements the `inertia ssr:stop` command.
///
/// ```dart
/// final exitCode = await InertiaSsrStopCommand().run();
/// ```
///
/// Stops a running SSR server via HTTP.
class InertiaSsrStopCommand extends Command<int> {
  /// Creates the `ssr:stop` command.
  InertiaSsrStopCommand() {
    argParser
      ..addOption(
        'url',
        defaultsTo: 'http://127.0.0.1:13714',
        help: 'SSR server base URL (without /render).',
      )
      ..addOption('shutdown', help: 'Override the shutdown endpoint URL.');
  }

  @override
  /// The command name.
  String get name => 'ssr:stop';

  @override
  /// The command description.
  String get description => 'Stop the Inertia SSR server.';

  @override
  /// Runs the command and returns an exit code.
  Future<int> run() async {
    final io = this.io;
    final url = argResults?['url'] as String? ?? 'http://127.0.0.1:13714';
    final shutdown = argResults?['shutdown'] as String?;
    final baseUri = normalizeSsrBase(url);
    io.title('Stopping Inertia SSR');
    io.twoColumnDetail('URL', baseUri.toString());

    final ok = await stopSsrServer(
      endpoint: baseUri,
      shutdownEndpoint: shutdown == null ? null : Uri.parse(shutdown),
    );
    if (!ok) {
      io.error('Unable to connect to Inertia SSR server.');
      return 1;
    }

    io.success('Inertia SSR server stopped.');
    return 0;
  }
}
