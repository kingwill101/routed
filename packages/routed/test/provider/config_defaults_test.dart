import 'package:routed/src/config/config.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:test/test.dart';

void main() {
  test('builds defaults from documentation entries', () {
    const defaults = ConfigDefaults(
      docs: <ConfigDocEntry>[
        ConfigDocEntry(path: 'feature.enabled', defaultValue: true),
        ConfigDocEntry(path: 'feature.threshold', defaultValue: 5),
        ConfigDocEntry(path: 'feature.tags', defaultValue: <String>['a', 'b']),
        ConfigDocEntry(
          path: 'feature.metadata',
          defaultValue: <String, Object?>{'mode': 'strict'},
        ),
      ],
    );

    final map = defaults.values;
    expect(map['feature'], isA<Map<String, Object?>>());
    final feature = map['feature'] as Map<String, Object?>;
    expect(feature['enabled'], isTrue);
    expect(feature['threshold'], 5);
    expect(feature['tags'], ['a', 'b']);
    expect(feature['metadata'], {'mode': 'strict'});
  });

  test('user overrides win over defaults', () {
    const defaults = ConfigDefaults(
      docs: <ConfigDocEntry>[
        ConfigDocEntry(path: 'service.enabled', defaultValue: true),
        ConfigDocEntry(path: 'service.endpoint', defaultValue: 'http://local'),
      ],
    );

    final config = ConfigImpl(defaults.values)
      ..merge({
        'service': {'enabled': false},
      });

    expect(config.get('service.enabled'), isFalse);
    expect(config.get('service.endpoint'), 'http://local');
  });

  test('merges map defaults contributed at the same path', () {
    const defaults = ConfigDefaults(
      docs: <ConfigDocEntry>[
        ConfigDocEntry(
          path: 'http.middleware_sources',
          defaultValue: <String, Object?>{
            'routed.logging': <String, Object?>{
              'global': <String>['routed.logging.http'],
            },
          },
        ),
        ConfigDocEntry(
          path: 'http.middleware_sources',
          defaultValue: <String, Object?>{
            'routed.sessions': <String, Object?>{
              'groups': <String, Object?>{
                'web': <String>['routed.sessions.start'],
              },
            },
          },
        ),
      ],
    );

    final http = defaults.values['http'] as Map<String, dynamic>;
    final sources = http['middleware_sources'] as Map<String, dynamic>;
    final logging = sources['routed.logging'] as Map<String, dynamic>;
    final sessions = sources['routed.sessions'] as Map<String, dynamic>;

    expect(logging['global'], equals(['routed.logging.http']));
    final groups = sessions['groups'] as Map<String, dynamic>;
    expect(groups['web'], equals(['routed.sessions.start']));
  });

  test(
    'snapshot evaluates lazy defaults once and preserves option builders',
    () {
      var defaultCalls = 0;
      var optionsCalls = 0;
      final defaults = ConfigDefaults(
        docs: <ConfigDocEntry>[
          ConfigDocEntry(
            path: 'feature.driver',
            defaultValueBuilder: () {
              defaultCalls += 1;
              return 'dynamic-driver';
            },
            optionsBuilder: () {
              optionsCalls += 1;
              return <String>['stack', 'single'];
            },
          ),
        ],
      );

      final snapshot = defaults.snapshot();
      final feature = snapshot.values['feature'] as Map<String, dynamic>;
      expect(feature['driver'], equals('dynamic-driver'));
      final doc = snapshot.docs.single;
      expect(doc.defaultValue, equals('dynamic-driver'));
      expect(doc.resolveOptions(), equals(<String>['stack', 'single']));
      expect(defaultCalls, equals(1));
      expect(optionsCalls, equals(1));
    },
  );
}
