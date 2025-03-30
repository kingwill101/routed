import 'dart:math' as math;

import '../generator_base.dart';

/// Generator for URI values
/// A generator that produces [Uri] objects.
///
/// Allows configuration of allowed `schemes`, inclusion of `userInfo`, `fragment`,
/// and `queryParameters`. Constraints `maxPathSegments` and `maxQueryParameters`
/// control the complexity of generated URIs. Generates plausible hostnames and
/// path/query components.
///
/// Shrinking attempts to remove components like path segments, query parameters,
/// fragments, and user info, and simplifies the host to common examples like
/// 'example.com'.
///
/// Usually used via [Specialized.uri].
///
/// ```dart
/// final uriGen = Specialized.uri(
///   schemes: ['https', 'http'],
///   includeQueryParameters: false,
/// );
/// final runner = PropertyTestRunner(uriGen, (uri) {
///   // Test property with generated Uri
/// });
/// await runner.run();
/// ```
class UriGenerator extends Generator<Uri> {
  final List<String> schemes;
  final bool includeUserInfo;
  final bool includeFragment;
  final bool includeQueryParameters;
  final int maxPathSegments;
  final int maxQueryParameters;

  static const _defaultSchemes = ['http', 'https', 'ftp', 'file'];
  static const _defaultTlds = ['.com', '.org', '.net', '.edu', '.gov'];
  static const _validDomainChars = 'abcdefghijklmnopqrstuvwxyz0123456789-';

  UriGenerator({
    List<String>? schemes,
    this.includeUserInfo = false,
    this.includeFragment = true,
    this.includeQueryParameters = true,
    this.maxPathSegments = 5,
    this.maxQueryParameters = 5,
  }) : schemes = schemes ?? _defaultSchemes;

  @override
  ShrinkableValue<Uri> generate(math.Random random) {
    final scheme = schemes[random.nextInt(schemes.length)];
    final host = _generateHost(random);
    final pathSegments = _generatePathSegments(random);
    final queryParameters = includeQueryParameters
        ? _generateQueryParameters(random)
        : <String, String>{};
    final fragment = includeFragment ? _generateFragment(random) : null;
    final userInfo = includeUserInfo ? _generateUserInfo(random) : null;

    final uri = Uri(
      scheme: scheme,
      userInfo: userInfo,
      host: host,
      pathSegments: pathSegments,
      queryParameters: queryParameters,
      fragment: fragment,
    );

    return ShrinkableValue(uri, () sync* {
      // Try removing path segments
      if (pathSegments.isNotEmpty) {
        yield ShrinkableValue.leaf(uri.replace(
          pathSegments: pathSegments.sublist(0, pathSegments.length - 1),
        ));
      }

      // Try removing query parameters
      if (queryParameters.isNotEmpty) {
        final simplified = Map<String, String>.from(queryParameters);
        simplified.remove(simplified.keys.first);
        yield ShrinkableValue.leaf(uri.replace(
          queryParameters: simplified,
        ));
      }

      // Try removing fragment
      if (fragment != null) {
        yield ShrinkableValue.leaf(uri.replace(fragment: null));
      }

      // Try removing user info
      if (userInfo != null) {
        yield ShrinkableValue.leaf(uri.replace(userInfo: null));
      }

      // Try common hosts
      final commonHosts = [
        'example.com',
        'localhost',
        'test.com',
      ];

      for (final host in commonHosts) {
        yield ShrinkableValue.leaf(uri.replace(host: host));
      }
    });
  }

  String _generateHost(math.Random random) {
    // Generate 2-4 parts for the domain
    final numParts = random.nextInt(3) + 2;
    final parts = <String>[];

    for (var i = 0; i < numParts - 1; i++) {
      // Each part must be 1-63 characters
      final length = random.nextInt(10) + 1;
      final buffer = StringBuffer();

      // First character must be alphanumeric
      buffer.write(_validDomainChars[random.nextInt(36)]); // Only a-z0-9

      // Generate remaining characters
      for (var j = 1; j < length; j++) {
        buffer
            .write(_validDomainChars[random.nextInt(_validDomainChars.length)]);
      }

      parts.add(buffer.toString());
    }

    // Add TLD
    parts.add(_defaultTlds[random.nextInt(_defaultTlds.length)].substring(1));

    return parts.join('.');
  }

  List<String> _generatePathSegments(math.Random random) {
    final count = random.nextInt(maxPathSegments);
    return List.generate(
      count,
      (_) => _generatePathSegment(random),
    );
  }

  String _generatePathSegment(math.Random random) {
    final length = random.nextInt(10) + 1;
    final chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    return String.fromCharCodes(
      List.generate(
          length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  Map<String, String> _generateQueryParameters(math.Random random) {
    final count = random.nextInt(maxQueryParameters);
    return Map.fromEntries(
      List.generate(count, (_) {
        final key = _generateQueryComponent(random);
        final value = _generateQueryComponent(random);
        return MapEntry(key, value);
      }),
    );
  }

  String _generateQueryComponent(math.Random random) {
    final length = random.nextInt(10) + 1;
    final chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    return String.fromCharCodes(
      List.generate(
          length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  String _generateFragment(math.Random random) =>
      _generateQueryComponent(random);

  String _generateUserInfo(math.Random random) {
    final username = _generateQueryComponent(random);
    final password = _generateQueryComponent(random);
    return '$username:$password';
  }
}
