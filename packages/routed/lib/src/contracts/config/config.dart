import 'dart:async';

import 'package:server_contracts/server_contracts.dart' as contracts;
import 'package:routed/src/config/runtime.dart' as config_runtime;

abstract class Config implements contracts.Config {
  /// Retrieves the configuration associated with the current AppZone.
  static Config get current => config_runtime.currentConfig();

  /// Runs [body] with the given [config] bound for the lifetime of that call.
  ///
  /// The provided configuration becomes accessible via [Config.current] and
  /// container resolution within the current zone until the callback completes.
  static FutureOr<T> runWith<T>(Config config, FutureOr<T> Function() body) {
    return config_runtime.runWithConfig(config, body);
  }
}
