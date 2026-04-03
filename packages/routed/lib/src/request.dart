import 'package:routed/src/engine/config.dart';
import 'package:routed_core/routed_core.dart' as core;

export 'package:routed_core/routed_core.dart' show RequestConfig;

class Request extends core.Request {
  Request(
    super.httpRequest,
    super.pathParameters,
    EngineConfig super.config,
  );

  @override
  EngineConfig get config => super.config as EngineConfig;
}
