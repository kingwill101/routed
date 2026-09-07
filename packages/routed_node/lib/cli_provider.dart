/// Conditionally contributes routed_node CLI commands to an application.
///
/// The JavaScript implementation is empty, so importing this helper from an
/// application that is also compiled for Cloudflare does not pull the CLI's
/// `dart:io` dependencies into the Worker bundle.
library;

export 'src/cli/provider_stub.dart'
    if (dart.library.io) 'src/cli/provider_io.dart';
