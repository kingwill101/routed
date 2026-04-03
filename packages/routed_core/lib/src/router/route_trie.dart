import 'dart:io';

/// Match result returned by [RouteTrie.match].
class RouteTrieMatch<T> {
  const RouteTrieMatch({required this.route, required this.pathMatched});

  final T? route;
  final bool pathMatched;
}

/// A generic segment trie for matching route-like path patterns.
class RouteTrie<T> {
  RouteTrie._(this._root, this._validateRoute);

  final _RouteTrieNode<T> _root;
  final bool Function(T route, HttpRequest request) _validateRoute;

  factory RouteTrie.fromRoutes(
    List<T> routes, {
    required String Function(T route) pathOf,
    required bool Function(T route, HttpRequest request) validate,
  }) {
    final root = _RouteTrieNode<T>();
    for (final route in routes) {
      root.add(route, pathOf);
    }
    return RouteTrie._(root, validate);
  }

  RouteTrieMatch<T> match(String path, HttpRequest request) {
    final segments = _splitSegments(path);
    T? matched;
    var pathMatched = false;

    bool search(_RouteTrieNode<T> node, int index) {
      if (index == segments.length) {
        if (node.terminalRoutes.isNotEmpty) {
          pathMatched = true;
          for (final route in node.terminalRoutes) {
            if (_validateRoute(route, request)) {
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
          if (_validateRoute(route, request)) {
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

class _RouteTrieNode<T> {
  final Map<String, _RouteTrieNode<T>> literals = {};
  _RouteTrieNode<T>? param;
  _RouteTrieNode<T>? wildcard;
  final List<T> terminalRoutes = [];

  void add(T route, String Function(T route) pathOf) {
    final segments = RouteTrie._splitSegments(pathOf(route));
    _insert(route, segments, 0, this);
  }

  void _insert(T route, List<String> segments, int index, _RouteTrieNode<T> node) {
    if (index == segments.length) {
      node.terminalRoutes.add(route);
      return;
    }

    final segment = segments[index];
    final info = _segmentInfo(segment);

    if (info.isWildcard) {
      node.wildcard ??= _RouteTrieNode<T>();
      node.wildcard!.terminalRoutes.add(route);
      return;
    }

    if (info.isParam) {
      if (info.isOptional) {
        _insert(route, segments, index + 1, node);
      }
      node.param ??= _RouteTrieNode<T>();
      _insert(route, segments, index + 1, node.param!);
      return;
    }

    final next = node.literals.putIfAbsent(segment, _RouteTrieNode<T>.new);
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
