// GENERATED CODE - DO NOT MODIFY BY HAND.
// Environment: development

import 'package:routed/routed.dart';

const String routedConfigEnvironment = 'development';
const Map<String, dynamic> routedConfig = <String, dynamic>{
  'app': <String, dynamic>{
    'debug': '{{ env.APP_DEBUG | default: true }}',
    'env': '{{ env.APP_ENV | default: \'development\' }}',
    'greeting': 'Hello {{ env.APP_GREETING_NAME | default: \'friend\' }}!',
    'name': '{{ env.APP_NAME | default: \'Config Demo\' }}',
    'root':
        '/run/media/kingwill101/disk2/code/code/dart_packages/routed_ecosystem/examples/config_demo',
  },
  'app_greeting_name': 'Routed',
  'cache': <String, dynamic>{
    'default': 'session',
    'stores': <String, dynamic>{
      'session': <String, dynamic>{
        'driver': 'in_memory',
        'namespace': 'config-demo:',
        'ttl': 180,
      },
    },
  },
  'features': <String, dynamic>{'beta_banner': 'false'},
  'http': <String, dynamic>{
    'middleware': <String, dynamic>{
      'global': <dynamic>[],
      'groups': <String, dynamic>{},
    },
    'providers': <dynamic>[
      'routed.core',
      'routed.routing',
      'routed.cache',
      'routed.storage',
      'routed.sessions',
      'routed.uploads',
      'routed.cors',
      'routed.security',
      'routed.logging',
      'routed.static',
      'config_demo.mail',
    ],
    'runtime': <String, dynamic>{
      'shutdown': <String, dynamic>{
        'enabled': true,
        'exit_code': 0,
        'force_after': '20s',
        'grace_period': '5s',
        'notify_readiness': true,
        'signals': <dynamic>['sigint', 'sigterm'],
      },
    },
  },
  'logging': <String, dynamic>{
    'extra_fields': <String, dynamic>{
      'deployment': 'liquid-demo',
      'service': 'config_demo',
    },
    'format': 'pretty',
    'request_headers': <dynamic>['X-Request-ID', 'X-Trace-ID'],
  },
  'mail': <String, dynamic>{
    'credentials': <String, dynamic>{
      'password': 's3cr3t',
      'username': 'config-demo',
    },
    'driver': 'smtp',
    'from': 'config-demo@example.dev',
    'host': 'smtp.dev.internal',
    'port': 2526,
  },
  'security': <String, dynamic>{
    'headers': <String, dynamic>{
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'referrer-policy': 'strict-origin-when-cross-origin',
    },
  },
  'session': <String, dynamic>{
    'config': <String, dynamic>{
      'app_key': '+vHSi+A+eKz4PUNY7wr9W1jWxCeV2365hjbCpWuskU4=',
      'cookie_name': 'config_demo_session',
      'driver': 'cookie',
      'http_only': true,
      'same_site': 'lax',
      'secure': false,
    },
  },
  'static': <String, dynamic>{
    'enabled': true,
    'mounts': <dynamic>[
      <String, dynamic>{
        'disk': 'assets',
        'path': 'public/assets',
        'route': '/assets',
      },
    ],
  },
  'storage': <String, Object?>{
    'default': 'assets',
    'disks': <String, dynamic>{
      'assets': <String, dynamic>{'driver': 'local', 'root': 'public/assets'},
      'transient': <String, dynamic>{
        'driver': 'memory_ephemeral',
        'root': 'runtime/transient',
        'seed': 'demo-seed',
      },
    },
  },
  'uploads': <String, dynamic>{
    'allowed_extensions': <dynamic>['jpg', 'png', 'pdf'],
    'max_file_size': 6291456,
  },
};

/// Resolves any `{{ env.* }}` placeholders left in
/// [routedConfig] using the current process environment and
/// returns a ready-to-use [ConfigSnapshot].
ConfigSnapshot resolveRoutedConfig() {
  final loader = ConfigLoader();
  final context = buildEnvTemplateContext();
  final resolved = loader.renderDefaults(routedConfig, context);
  return ConfigSnapshot(
    config: ConfigImpl(resolved),
    environment: routedConfigEnvironment,
  );
}
