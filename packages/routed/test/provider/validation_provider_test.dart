import 'package:routed/routed.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

void main() {
  group('Provider configuration validation', () {
    test(
      'surface descriptive error for static provider invalid mount',
      () async {
        await expectLater(
          () => testEngine(
            configItems: {
              'static': {
                'enabled': true,
                'mounts': [
                  {
                    'route': '/broken',
                    'disk': 123, // invalid type
                  },
                ],
              },
            },
          ),
          throwsA(
            isA<ProviderConfigException>().having(
              (e) => e.message,
              'message',
              contains('static.mounts[0].disk must be a string'),
            ),
          ),
        );
      },
    );

    test('surface descriptive error for logging request headers', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'logging': {
              'request_headers': ['X-Valid', 123],
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('logging.request_headers[1] must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error for cors allowed origins', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'cors': {
              'allowed_origins': ['https://ok', 123],
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('cors.allowed_origins[1] must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error for cors enabled flag', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'cors': {'enabled': 'maybe'},
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('cors.enabled must be a boolean'),
          ),
        ),
      );
    });

    test('surface descriptive error for rate limit policies', () async {
      await expectLater(
        () async {
          final engine = testEngine(
            configItems: {
              'rate_limit': {
                'enabled': false,
                'policies': ['bad'],
              },
            },
          );
          try {
            await engine.initialize();
          } finally {
            await engine.close();
          }
        },
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('rate_limit.policies[0] must be a map'),
          ),
        ),
      );
    });

    test('surface descriptive error for uploads max memory', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'uploads': {'max_memory': 'abc'},
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('uploads.max_memory must be an integer'),
          ),
        ),
      );
    });

    test('surface descriptive error for uploads allowed extensions', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'uploads': {
              'allowed_extensions': ['png', 123],
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('uploads.allowed_extensions[1] must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error for security trusted proxies', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'security': {
              'trusted_proxies': {
                'proxies': ['10.0.0.0/8', 42],
              },
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('security.trusted_proxies.proxies[1] must be a string'),
          ),
        ),
      );
    });

    test(
      'surface descriptive error for security trusted proxies type',
      () async {
        await expectLater(
          () => testEngine(
            configItems: {
              'security': {'trusted_proxies': 'invalid'},
            },
          ),
          throwsA(
            isA<ProviderConfigException>().having(
              (e) => e.message,
              'message',
              contains('security.trusted_proxies must be a map'),
            ),
          ),
        );
      },
    );

    test(
      'surface descriptive error for security max_request_size type',
      () async {
        await expectLater(
          () => testEngine(
            configItems: {
              'security': {'max_request_size': 'abc'},
            },
          ),
          throwsA(
            isA<ProviderConfigException>().having(
              (e) => e.message,
              'message',
              contains('security.max_request_size must be an integer'),
            ),
          ),
        );
      },
    );

    test(
      'surface descriptive error for security max_request_size negative',
      () async {
        await expectLater(
          () => testEngine(
            configItems: {
              'security': {'max_request_size': -1},
            },
          ),
          throwsA(
            isA<ProviderConfigException>().having(
              (e) => e.message,
              'message',
              contains('security.max_request_size must be zero or positive'),
            ),
          ),
        );
      },
    );

    test('surface descriptive error for security headers map values', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'security': {
              'headers': {'Referrer-Policy': 123},
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('security.headers.Referrer-Policy must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error for security csrf map type', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'security': {'csrf': 'enabled'},
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('security.csrf must be a map'),
          ),
        ),
      );
    });

    test('surface descriptive error for security csrf enabled type', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'security': {
              'csrf': {'enabled': 'maybe'},
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('security.csrf.enabled must be a boolean'),
          ),
        ),
      );
    });

    test('surface descriptive error for security csrf cookie_name', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'security': {
              'csrf': {'cookie_name': 123},
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('security.csrf.cookie_name must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error when security root is not a map', () async {
      await expectLater(
        () => testEngine(configItems: {'security': 'invalid'}),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('security must be a map'),
          ),
        ),
      );
    });

    test('surface descriptive error for view directory type', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'view': {'directory': 42},
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('view.directory must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error for view cache type', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'view': {'cache': 'maybe'},
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('view.cache must be a boolean'),
          ),
        ),
      );
    });

    test('surface descriptive error for view engine type', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'view': {'engine': 123},
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('view.engine must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error for view disk type', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'view': {'disk': 123},
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('view.disk must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error when view node is not a map', () async {
      await expectLater(
        () => testEngine(configItems: {'view': 'invalid'}),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('view must be a map'),
          ),
        ),
      );
    });

    test('surface descriptive error when cache root is not a map', () async {
      await expectLater(
        () => testEngine(configItems: {'cache': 'invalid'}),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('cache must be a map'),
          ),
        ),
      );
    });

    test('surface descriptive error for cache default type', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'cache': {
              'default': 42,
              'stores': {
                'file': {'driver': 'file'},
              },
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('cache.default must be a string'),
          ),
        ),
      );
    });

    test('surface descriptive error for cache store type', () async {
      await expectLater(
        () => testEngine(
          configItems: {
            'cache': {
              'stores': {'file': 'invalid'},
            },
          },
        ),
        throwsA(
          isA<ProviderConfigException>().having(
            (e) => e.message,
            'message',
            contains('cache.stores.file must be a map'),
          ),
        ),
      );
    });
  });
}
