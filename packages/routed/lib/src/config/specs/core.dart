import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

class CoreConfig {
  const CoreConfig({
    required this.name,
    required this.env,
    required this.debug,
    required this.key,
    required this.url,
    required this.timezone,
    required this.locale,
    required this.fallbackLocale,
    required this.fakerLocale,
    required this.cipher,
    required this.cachePrefix,
    required this.previousKeys,
  });

  final String name;
  final String env;
  final bool debug;
  final String key;
  final String url;
  final String timezone;
  final String locale;
  final String fallbackLocale;
  final String fakerLocale;
  final String cipher;
  final String cachePrefix;
  final List<String> previousKeys;
}

class CoreConfigSpec extends ConfigSpec<CoreConfig> {
  const CoreConfigSpec();

  @override
  String get root => 'app';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Application Configuration',
    description: 'Core application settings.',
    properties: {
      'name': ConfigSchema.string(
        description: 'Application display name.',
        defaultValue: "{{ env.APP_NAME | default: 'Routed App' }}",
      ).withMetadata({configDocMetaInheritFromEnv: 'APP_NAME'}),
      'env': ConfigSchema.string(
        description:
            'Runtime environment identifier (development, production, etc.).',
        defaultValue: 'production',
      ).withMetadata({configDocMetaInheritFromEnv: 'APP_ENV'}),
      'debug': ConfigSchema.boolean(
        description: 'Enables verbose application debugging.',
        defaultValue: false,
      ).withMetadata({configDocMetaInheritFromEnv: 'APP_DEBUG'}),
      'key': ConfigSchema.string(
        description: 'Application encryption key used for signed payloads.',
        defaultValue: "{{ env.APP_KEY | default: 'change-me' }}",
      ).withMetadata({configDocMetaInheritFromEnv: 'APP_KEY'}),
      'url': ConfigSchema.string(
        description: 'Base URL used in generated links.',
        defaultValue: 'http://localhost',
      ),
      'timezone': ConfigSchema.string(
        description: 'Default timezone applied to dates.',
        defaultValue: 'UTC',
      ),
      'locale': ConfigSchema.string(
        description: 'Primary locale identifier used for localized content.',
        defaultValue: 'en',
      ),
      'fallback_locale': ConfigSchema.string(
        description: 'Locale used when a translation key is missing.',
        defaultValue: 'en',
      ),
      'faker_locale': ConfigSchema.string(
        description: 'Locale applied to Faker-generated seed data.',
        defaultValue: 'en_US',
      ),
      'cipher': ConfigSchema.string(
        description: 'Default cipher used for encrypted payloads.',
        defaultValue: 'AES-256-CBC',
      ),
      'cache_prefix': ConfigSchema.string(
        description:
            'Prefix applied to cache keys for array and simple stores.',
        defaultValue: '',
      ),
      'previous_keys': ConfigSchema.list(
        description: 'Previous APP_KEY values accepted during key rotation.',
        items: ConfigSchema.string(),
        defaultValue: const [],
      ),
      'maintenance': ConfigSchema.object(
        properties: {
          'driver': ConfigSchema.string(
            description: 'Driver responsible for toggling maintenance mode.',
            defaultValue: 'file',
          ),
          'store': ConfigSchema.string(
            description: 'Backing store used by the maintenance driver.',
            defaultValue: 'database',
          ),
        },
      ),
    },
  );

  @override
  CoreConfig fromMap(Map<String, dynamic> map, {ConfigSpecContext? context}) {
    return CoreConfig(
      name: parseStringLike(map['name'], context: 'app.name') ?? 'Routed App',
      env: parseStringLike(map['env'], context: 'app.env') ?? 'production',
      debug: parseBoolLike(map['debug'], context: 'app.debug') ?? false,
      key: parseStringLike(map['key'], context: 'app.key') ?? 'change-me',
      url:
          parseStringLike(map['url'], context: 'app.url') ?? 'http://localhost',
      timezone:
          parseStringLike(map['timezone'], context: 'app.timezone') ?? 'UTC',
      locale: parseStringLike(map['locale'], context: 'app.locale') ?? 'en',
      fallbackLocale:
          parseStringLike(
            map['fallback_locale'],
            context: 'app.fallback_locale',
          ) ??
          'en',
      fakerLocale:
          parseStringLike(map['faker_locale'], context: 'app.faker_locale') ??
          'en_US',
      cipher:
          parseStringLike(map['cipher'], context: 'app.cipher') ??
          'AES-256-CBC',
      cachePrefix:
          parseStringLike(map['cache_prefix'], context: 'app.cache_prefix') ??
          '',
      previousKeys:
          parseStringList(map['previous_keys'], context: 'app.previous_keys') ??
          const [],
    );
  }

  @override
  Map<String, dynamic> toMap(CoreConfig value) {
    return {
      'name': value.name,
      'env': value.env,
      'debug': value.debug,
      'key': value.key,
      'url': value.url,
      'timezone': value.timezone,
      'locale': value.locale,
      'fallback_locale': value.fallbackLocale,
      'faker_locale': value.fakerLocale,
      'cipher': value.cipher,
      'cache_prefix': value.cachePrefix,
      'previous_keys': value.previousKeys,
    };
  }
}
