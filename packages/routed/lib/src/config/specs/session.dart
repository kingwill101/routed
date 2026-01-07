import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/secure_cookie.dart';

import '../spec.dart';

StorageDefaults _sessionBaselineStorage() =>
    StorageDefaults.fromLocalRoot('storage/app');

class SessionProviderConfig {
  const SessionProviderConfig({
    required this.enabled,
    required this.raw,
    required this.driver,
    required this.cookieName,
    required this.lifetime,
    required this.expireOnClose,
    required this.encrypt,
    required this.options,
    required this.codecs,
    required this.cachePrefix,
    required this.keys,
    required this.lottery,
  });

  final bool enabled;
  final Map<String, dynamic> raw;
  final String driver;
  final String cookieName;
  final Duration lifetime;
  final bool expireOnClose;
  final bool encrypt;
  final Options options;
  final List<SecureCookie> codecs;
  final String cachePrefix;
  final List<String> keys;
  final List<int>? lottery;

  factory SessionProviderConfig.fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final merged = Map<String, dynamic>.from(map);
    if (merged.containsKey('config')) {
      final configValue = merged['config'];
      if (configValue != null) {
        final configMap = stringKeyedMap(
          configValue as Object,
          'session.config',
        );
        merged.addAll(configMap);
      }
    }

    final enabled =
        parseBoolLike(
          merged['enabled'],
          context: 'session.enabled',
          throwOnInvalid: true,
        ) ??
        false;

    final driverRaw = parseStringLike(
      merged['driver'],
      context: 'session.driver',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final driver = (driverRaw == null || driverRaw.isEmpty)
        ? 'cookie'
        : driverRaw.toLowerCase();

    final cookieName =
        parseStringLike(
          merged['cookie'],
          context: 'session.cookie',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        parseStringLike(
          merged['cookie_name'],
          context: 'session.cookie_name',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        parseStringLike(
          merged['name'],
          context: 'session.name',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        _defaultCookieName(context?.config);

    final lifetime = _resolveLifetime(merged);
    final expireOnClose =
        parseBoolLike(
          merged['expire_on_close'],
          context: 'session.expire_on_close',
          throwOnInvalid: true,
        ) ??
        false;
    final encrypt =
        parseBoolLike(
          merged['encrypt'],
          context: 'session.encrypt',
          throwOnInvalid: true,
        ) ??
        (driver == 'cookie');

    final cookiePath =
        parseStringLike(
          merged['path'],
          context: 'session.path',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        '/';
    final domain =
        parseStringLike(
          merged['domain'],
          context: 'session.domain',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        parseStringLike(
          merged['cookie_domain'],
          context: 'session.cookie_domain',
          allowEmpty: true,
          throwOnInvalid: true,
        );
    final secure = parseBoolLike(
      merged['secure'],
      context: 'session.secure',
      throwOnInvalid: true,
    );
    final httpOnly =
        parseBoolLike(
          merged['http_only'],
          context: 'session.http_only',
          throwOnInvalid: true,
        ) ??
        true;
    final sameSite = _parseSameSite(merged['same_site']);
    final partitioned = parseBoolLike(
      merged['partitioned'],
      context: 'session.partitioned',
      throwOnInvalid: true,
    );
    final lottery = _parseLottery(merged['lottery']);
    final cachePrefix =
        parseStringLike(
          merged['cache_prefix'],
          context: 'session.cache_prefix',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'session:';

    final options = Options(
      path: cookiePath,
      domain: domain,
      maxAge: expireOnClose ? null : lifetime.inSeconds,
      secure: secure,
      httpOnly: httpOnly,
      sameSite: sameSite,
      partitioned: partitioned,
    );

    if (!enabled) {
      return SessionProviderConfig(
        enabled: enabled,
        raw: merged,
        driver: driver,
        cookieName: cookieName,
        lifetime: lifetime,
        expireOnClose: expireOnClose,
        encrypt: encrypt,
        options: options,
        codecs: const <SecureCookie>[],
        cachePrefix: cachePrefix,
        keys: const <String>[],
        lottery: lottery,
      );
    }

    final keys = _resolveKeys(merged, context?.config);
    if (keys.isEmpty) {
      throw ProviderConfigException(
        'session.app_key or app.key is required for session cookies.',
      );
    }

    late final List<SecureCookie> codecs;
    try {
      codecs = <SecureCookie>[
        SecureCookie(key: keys.first, useEncryption: encrypt, useSigning: true),
        ...keys
            .skip(1)
            .map(
              (key) => SecureCookie(
                key: key,
                useEncryption: encrypt,
                useSigning: true,
              ),
            ),
      ];
    } on FormatException catch (error) {
      throw ProviderConfigException(
        'session.app_key or app.key must be a valid base64-encoded key: '
        '${error.message}',
      );
    }

    return SessionProviderConfig(
      enabled: enabled,
      raw: merged,
      driver: driver,
      cookieName: cookieName,
      lifetime: lifetime,
      expireOnClose: expireOnClose,
      encrypt: encrypt,
      options: options,
      codecs: codecs,
      cachePrefix: cachePrefix,
      keys: keys,
      lottery: lottery,
    );
  }

  static Duration _resolveLifetime(Map<String, dynamic> source) {
    final lifetimeRaw = parseIntLike(
      source['lifetime'],
      context: 'session.lifetime',
      throwOnInvalid: true,
    );
    if (lifetimeRaw != null) {
      return Duration(minutes: lifetimeRaw);
    }
    final maxAgeRaw = parseIntLike(
      source['max_age'],
      context: 'session.max_age',
      throwOnInvalid: true,
    );
    if (maxAgeRaw != null) {
      return Duration(seconds: maxAgeRaw);
    }
    return const Duration(minutes: 120);
  }

  static List<String> _resolveKeys(Map<String, dynamic> map, Config? root) {
    final candidates = <String?>[
      parseStringLike(
        map['key'],
        context: 'session.key',
        allowEmpty: true,
        throwOnInvalid: true,
      ),
      parseStringLike(
        map['app_key'],
        context: 'session.app_key',
        allowEmpty: true,
        throwOnInvalid: true,
      ),
      parseStringLike(
        map['secret'],
        context: 'session.secret',
        allowEmpty: true,
        throwOnInvalid: true,
      ),
      _rootString(root, 'session.app_key'),
      _rootString(root, 'app.key'),
    ];

    final result = <String>[];
    for (final candidate in candidates) {
      final normalized = _normalizeKey(candidate);
      if (normalized != null) {
        result.add(normalized);
        break;
      }
    }

    final additional = <String>[
      ...?parseStringList(
        map['previous_keys'],
        context: 'session.previous_keys',
        allowEmptyResult: false,
        throwOnInvalid: true,
      ),
      ...?_rootStringList(root, 'session.previous_keys'),
      ...?_rootStringList(root, 'app.previous_keys'),
    ];
    for (final key in additional) {
      final normalized = _normalizeKey(key);
      if (normalized != null && !result.contains(normalized)) {
        result.add(normalized);
      }
    }

    return result;
  }

  static String? _rootString(Config? root, String path) {
    if (root == null) {
      return null;
    }
    return parseStringLike(
      root.get<Object?>(path),
      context: path,
      allowEmpty: true,
      throwOnInvalid: true,
    );
  }

  static List<String>? _rootStringList(Config? root, String path) {
    if (root == null) {
      return null;
    }
    return parseStringList(
      root.get<Object?>(path),
      context: path,
      allowEmptyResult: false,
      throwOnInvalid: true,
    );
  }

  static String? _normalizeKey(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = base64.decode(trimmed);
      if (decoded.length >= 32) {
        return trimmed;
      }
      final digest = crypto.sha256.convert(decoded).bytes;
      return base64.encode(digest);
    } catch (_) {
      final digest = crypto.sha256.convert(utf8.encode(trimmed)).bytes;
      return base64.encode(digest);
    }
  }

  static String _defaultCookieName(Config? config) {
    final appName = _rootString(config, 'app.name') ?? 'routed';
    final slug = appName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${slug.isEmpty ? 'routed' : slug}-session';
  }

  static SameSite? _parseSameSite(Object? value) {
    final normalized = parseStringLike(
      value,
      context: 'session.same_site',
      allowEmpty: true,
      throwOnInvalid: true,
    )?.toLowerCase();
    switch (normalized) {
      case null:
      case '':
      case 'null':
        return null;
      case 'lax':
        return SameSite.lax;
      case 'strict':
        return SameSite.strict;
      case 'none':
        return SameSite.none;
      default:
        throw ProviderConfigException(
          'session.same_site must be "lax", "strict", "none", or null',
        );
    }
  }

  static List<int>? _parseLottery(Object? value) {
    if (value == null) return null;
    final list =
        parseIntList(
          value,
          context: 'session.lottery',
          allowEmptyResult: true,
          allowInvalidStringEntries: true,
          throwOnInvalid: true,
        ) ??
        const <int>[];
    if (list.length == 2) {
      return list;
    }
    if (list.isEmpty) {
      return null;
    }
    throw ProviderConfigException('session.lottery must contain two integers.');
  }
}

class SessionConfigSpec extends ConfigSpec<SessionProviderConfig> {
  const SessionConfigSpec();

  @override
  String get root => 'session';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {
      'driver': 'cookie',
      'lifetime': 120,
      'expire_on_close': false,
      'encrypt': true,
      'cookie': "{{ env.SESSION_COOKIE | default: 'routed-session' }}",
      'path': '/',
      'secure': false,
      'http_only': true,
      'partitioned': false,
      'cache_prefix': 'session:',
      'same_site': 'lax',
      'files': _sessionBaselineStorage().frameworkPath('sessions'),
      'lottery': const [2, 100],
      'previous_keys': const <String>[],
    };
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('driver'),
        type: 'string',
        description: 'Session backend to use.',
        defaultValue: 'cookie',
        metadata: const {configDocMetaInheritFromEnv: 'SESSION_DRIVER'},
      ),
      ConfigDocEntry(
        path: path('lifetime'),
        type: 'int',
        description: 'Session lifetime in minutes.',
        defaultValue: 120,
      ),
      ConfigDocEntry(
        path: path('expire_on_close'),
        type: 'bool',
        description: 'Expire sessions when the browser closes.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: path('encrypt'),
        type: 'bool',
        description: 'Encrypt session payloads when using cookie drivers.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: path('cookie'),
        type: 'string',
        description:
            'Cookie name used for identifying the session when using cookie-based drivers.',
        example: 'routed_app_session',
        defaultValue: "{{ env.SESSION_COOKIE | default: 'routed-session' }}",
        metadata: {configDocMetaInheritFromEnv: 'SESSION_COOKIE'},
      ),
      ConfigDocEntry(
        path: path('path'),
        type: 'string',
        description: 'Cookie path scope for the session identifier.',
        defaultValue: '/',
      ),
      ConfigDocEntry(
        path: path('domain'),
        type: 'string',
        description: 'Cookie domain override for session cookies.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: path('secure'),
        type: 'bool',
        description: 'Require HTTPS when sending session cookies.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: path('http_only'),
        type: 'bool',
        description: 'Mark session cookies as HTTP-only.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: path('partitioned'),
        type: 'bool',
        description: 'Enable partitioned cookies for session storage.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: path('cache_prefix'),
        type: 'string',
        description:
            'Prefix applied to cache keys when using cache-backed session drivers.',
        defaultValue: 'session:',
      ),
      ConfigDocEntry(
        path: path('same_site'),
        type: 'string',
        description: 'SameSite policy applied to the session cookie.',
        options: <String>['lax', 'strict', 'none'],
        defaultValue: 'lax',
      ),
      ConfigDocEntry(
        path: path('files'),
        type: 'string',
        description: 'Filesystem path used by file-based session drivers.',
        defaultValueBuilder: () =>
            _sessionBaselineStorage().frameworkPath('sessions'),
      ),
      ConfigDocEntry(
        path: path('lottery'),
        type: 'list<int>',
        description:
            'Odds used by some drivers to trigger garbage collection (numerator, denominator).',
        defaultValue: [2, 100],
      ),
      ConfigDocEntry(
        path: path('previous_keys'),
        type: 'list<string>',
        description:
            'Historical keys accepted when rotating session secrets. New sessions always use the current key.',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: path('enabled'),
        type: 'bool',
        description:
            'Enable the built-in sessions middleware (defaults to disabled).',
        defaultValue: null,
      ),
    ];
  }

  @override
  SessionProviderConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    return SessionProviderConfig.fromMap(map, context: context);
  }

  @override
  Map<String, dynamic> toMap(SessionProviderConfig value) {
    return Map<String, dynamic>.from(value.raw);
  }
}
