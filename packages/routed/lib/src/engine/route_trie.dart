import 'dart:io';

import 'package:routed_core/routed_core.dart' as core;

import 'engine.dart' show EngineRoute;

class RouteTrieMatch extends core.RouteTrieMatch<EngineRoute> {
  const RouteTrieMatch({required super.route, required super.pathMatched});
}

class RouteTrie {
  RouteTrie._(this._inner);

  final core.RouteTrie<EngineRoute> _inner;

  factory RouteTrie.fromRoutes(List<EngineRoute> routes) {
    return RouteTrie._(
      core.RouteTrie.fromRoutes(
        routes,
        pathOf: (route) => route.path,
        validate: (route, request) => route.validateConstraints(request),
      ),
    );
  }

  RouteTrieMatch match(String path, HttpRequest request) {
    final result = _inner.match(path, request);
    return RouteTrieMatch(route: result.route, pathMatched: result.pathMatched);
  }
}
