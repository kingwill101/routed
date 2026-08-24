part of 'engine.dart';

/// The result of matching a request path against a route trie.
class RouteTrieMatch {
  /// Creates a match result with the matched [route] and path status.
  const RouteTrieMatch({required this.route, required this.pathMatched});

  /// The matched route, or `null` when constraints rejected all candidates.
  final EngineRoute? route;

  /// Whether the path shape matched at least one route.
  final bool pathMatched;
}

/// Segment trie used for fast route path matching.
class RouteTrie {
  /// Builds a trie from [routes].
  factory RouteTrie.fromRoutes(List<EngineRoute> routes) {
    final root = _RouteTrieNode();
    for (final route in routes) {
      root.add(route);
    }
    return RouteTrie._(root);
  }
  RouteTrie._(this._root);

  final _RouteTrieNode _root;

  /// Matches [path] and evaluates constraints against [request].
  /// Matches [path] against the trie.
  ///
  /// [request] may be an [HttpRequest], [RequestAdapter], or
  /// [ConstraintRequestView] (used only for constraint checks).
  RouteTrieMatch match(String path, Object request) {
    final segments = _splitSegments(path);
    EngineRoute? matched;
    var pathMatched = false;

    bool search(_RouteTrieNode node, int index) {
      if (index == segments.length) {
        if (node.terminalRoutes.isNotEmpty) {
          pathMatched = true;
          for (final route in node.terminalRoutes) {
            if (route.validateConstraints(request)) {
              matched = route;
              return true;
            }
          }
        }
        return false;
      }

      final segment = segments[index];

      final literal = node.literals[segment];
      if (literal != null && search(literal, index + 1)) {
        return true;
      }

      final param = node.param;
      if (param != null && search(param, index + 1)) {
        return true;
      }

      final wildcard = node.wildcard;
      if (wildcard != null && wildcard.terminalRoutes.isNotEmpty) {
        pathMatched = true;
        for (final route in wildcard.terminalRoutes) {
          if (route.validateConstraints(request)) {
            matched = route;
            return true;
          }
        }
      }

      return false;
    }

    search(_root, 0);
    return RouteTrieMatch(route: matched, pathMatched: pathMatched);
  }

  static List<String> _splitSegments(String path) {
    if (path.isEmpty || path == '/') {
      return const <String>[];
    }
    return path.split('/').where((segment) => segment.isNotEmpty).toList();
  }
}

class _RouteTrieNode {
  final Map<String, _RouteTrieNode> literals = {};
  _RouteTrieNode? param;
  _RouteTrieNode? wildcard;
  final List<EngineRoute> terminalRoutes = [];

  void add(EngineRoute route) {
    final segments = RouteTrie._splitSegments(route.path);
    _insert(route, segments, 0, this);
  }

  void _insert(
    EngineRoute route,
    List<String> segments,
    int index,
    _RouteTrieNode node,
  ) {
    if (index == segments.length) {
      node.terminalRoutes.add(route);
      return;
    }

    final segment = segments[index];
    final info = _segmentInfo(segment);

    if (info.isWildcard) {
      node.wildcard ??= _RouteTrieNode();
      node.wildcard!.terminalRoutes.add(route);
      return;
    }

    if (info.isParam) {
      if (info.isOptional) {
        _insert(route, segments, index + 1, node);
      }
      node.param ??= _RouteTrieNode();
      _insert(route, segments, index + 1, node.param!);
      return;
    }

    final next = node.literals.putIfAbsent(segment, _RouteTrieNode.new);
    _insert(route, segments, index + 1, next);
  }

  _SegmentInfo _segmentInfo(String segment) {
    if (!segment.startsWith('{') || !segment.endsWith('}')) {
      return const _SegmentInfo();
    }

    final token = segment.substring(1, segment.length - 1);
    final isWildcard = token.startsWith('*');
    final isOptional = token.endsWith('?');
    return _SegmentInfo(
      isParam: !isWildcard,
      isWildcard: isWildcard,
      isOptional: isOptional,
    );
  }
}

class _SegmentInfo {
  const _SegmentInfo({
    this.isParam = false,
    this.isWildcard = false,
    this.isOptional = false,
  });

  final bool isParam;
  final bool isWildcard;
  final bool isOptional;
}
