import 'dart:async';

import 'package:routed_core/src/contracts/contracts.dart';
import 'package:routed_core/src/support/zone.dart';

Config currentConfig() {
  return AppZone.config;
}

FutureOr<T> runWithConfig<T>(Config config, FutureOr<T> Function() body) {
  return AppZone.runWithConfig(config: config, body: body);
}
