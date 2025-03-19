import 'package:routed/routed.dart';

final _middlewareIdentityMap = <Middleware, String>{};

Middleware makeMiddleware(String label, List<String> log) {
  mw(EngineContext c) async {
    log.add(label);
    c.next();
  }

  _middlewareIdentityMap[mw] = label;
  return mw;
}

String middlewareLabel(Middleware mw, List<String> log) {
  return _middlewareIdentityMap[mw] ?? "UnknownMiddleware";
}

Engine engineWithFeatures({
  bool enableProxySupport = false,
  bool enableTrustedPlatform = false,
}) {
  return Engine(
      config: EngineConfig(
          features: EngineFeatures(
              enableProxySupport: enableProxySupport,
              enableTrustedPlatform: enableTrustedPlatform)));
}
