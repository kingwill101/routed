import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

class SessionDriverSpecContext extends ConfigSpecContext {
  const SessionDriverSpecContext({
    required this.driver,
    required this.pathBase,
    super.config,
  });

  final String driver;
  final String pathBase;

  String path(String segment) =>
      pathBase.isEmpty ? segment : '$pathBase.$segment';
}

String _pathFor(ConfigSpecContext? context, String fallbackBase, String segment) {
  final base =
      context is SessionDriverSpecContext ? context.pathBase : fallbackBase;
  return base.isEmpty ? segment : '$base.$segment';
}

class SessionCookieDriverConfig {
  const SessionCookieDriverConfig();
}

class SessionCookieDriverSpec extends ConfigSpec<SessionCookieDriverConfig> {
  const SessionCookieDriverSpec();

  @override
  String get root => 'session';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return const <String, dynamic>{};
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) =>
        base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('encrypt'),
        type: 'bool',
        description:
            'Controls whether cookie-based session payloads are encrypted.',
      ),
    ];
  }

  @override
  SessionCookieDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    return const SessionCookieDriverConfig();
  }

  @override
  Map<String, dynamic> toMap(SessionCookieDriverConfig value) {
    return const <String, dynamic>{};
  }
}

class SessionFileDriverConfig {
  const SessionFileDriverConfig({this.storagePath, this.lottery});

  final String? storagePath;
  final List<int>? lottery;
}

class SessionFileDriverSpec extends ConfigSpec<SessionFileDriverConfig> {
  const SessionFileDriverSpec();

  @override
  String get root => 'session';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return const <String, dynamic>{};
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) =>
        base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('files'),
        type: 'string',
        description:
            'Directory path used to persist session files. Defaults to '
            'storage/framework/sessions based on your storage configuration.',
        metadata: const {
          'default_note':
              'Computed from storage defaults (storage/framework/sessions).',
          'validation': 'Must resolve to an accessible directory path.',
        },
      ),
      ConfigDocEntry(
        path: path('lottery'),
        type: 'list<int>',
        description:
            'Cleanup lottery odds for pruning stale sessions (e.g., [2, 100]).',
        defaultValue: const [2, 100],
        metadata: const {'validation': 'Provide two integers [wins, total].'},
      ),
    ];
  }

  @override
  SessionFileDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final storagePath =
        parseStringLike(
          map['files'],
          context: _pathFor(context, root, 'files'),
          allowEmpty: true,
          coerceNonString: true,
          throwOnInvalid: false,
        ) ??
        parseStringLike(
          map['storage_path'],
          context: _pathFor(context, root, 'storage_path'),
          allowEmpty: true,
          coerceNonString: true,
          throwOnInvalid: false,
        ) ??
        parseStringLike(
          map['path'],
          context: _pathFor(context, root, 'path'),
          allowEmpty: true,
          coerceNonString: true,
          throwOnInvalid: false,
        );

    final lottery = _parseLottery(map['lottery'], context);

    return SessionFileDriverConfig(storagePath: storagePath, lottery: lottery);
  }

  @override
  Map<String, dynamic> toMap(SessionFileDriverConfig value) {
    final map = <String, dynamic>{};
    if (value.storagePath != null) {
      map['files'] = value.storagePath;
    }
    if (value.lottery != null) {
      map['lottery'] = value.lottery;
    }
    return map;
  }

  List<int>? _parseLottery(Object? value, ConfigSpecContext? context) {
    if (value == null) return null;
    final list =
        parseIntList(
          value,
          context: _pathFor(context, root, 'lottery'),
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

class SessionArrayDriverConfig {
  const SessionArrayDriverConfig();
}

class SessionArrayDriverSpec extends ConfigSpec<SessionArrayDriverConfig> {
  const SessionArrayDriverSpec();

  @override
  String get root => 'session';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return const <String, dynamic>{};
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    return const <ConfigDocEntry>[];
  }

  @override
  SessionArrayDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    return const SessionArrayDriverConfig();
  }

  @override
  Map<String, dynamic> toMap(SessionArrayDriverConfig value) {
    return const <String, dynamic>{};
  }
}

class SessionCacheDriverConfig {
  const SessionCacheDriverConfig({this.store});

  final String? store;

  String resolveStoreName(String driver) {
    if (store == null || store!.isEmpty) {
      return driver == 'database' ? 'database' : driver;
    }
    return store!;
  }
}

class SessionCacheDriverSpec extends ConfigSpec<SessionCacheDriverConfig> {
  const SessionCacheDriverSpec();

  @override
  String get root => 'session';

  @override
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return const <String, dynamic>{};
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) =>
        base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('store'),
        type: 'string',
        description:
            'Cache store name used when persisting sessions via cache-backed drivers. '
            'Defaults to the driver name when omitted.',
        metadata: const {
          'validation': 'Must match a configured cache store name.',
        },
      ),
    ];
  }

  @override
  SessionCacheDriverConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final storeRaw = parseStringLike(
      map['store'],
      context: _pathFor(context, root, 'store'),
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final store = (storeRaw == null || storeRaw.isEmpty) ? null : storeRaw;
    return SessionCacheDriverConfig(store: store);
  }

  @override
  Map<String, dynamic> toMap(SessionCacheDriverConfig value) {
    final map = <String, dynamic>{};
    if (value.store != null) {
      map['store'] = value.store;
    }
    return map;
  }
}
