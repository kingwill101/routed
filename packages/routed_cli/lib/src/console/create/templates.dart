import 'dart:convert';

import 'package:routed_cli/src/console/create/templates_embedded.dart';

/// Renders one scaffold file for a [TemplateContext].
typedef FileBuilder = String Function(TemplateContext context);

/// Values used when rendering a project scaffold.
///
/// [TemplateContext] is passed to every [FileBuilder]. Built-in templates use
/// it to keep generated package metadata, display text, and sample data
/// consistent across `pubspec.yaml`, `README.md`, and application files.
class TemplateContext {
  /// Creates a context for a project named [packageName].
  TemplateContext({
    required this.packageName,
    required this.humanName,
    Iterable<String> authPlugins = const [],
  }) : authPlugins = Set<String>.unmodifiable(authPlugins);

  /// Dart package name used by generated imports and metadata.
  final String packageName;

  /// Human-readable project name used in generated copy.
  final String humanName;

  /// Authentication plugin identifiers selected for the scaffold.
  ///
  /// The set controls which typed auth dependencies and provider wiring are
  /// emitted by the selected template. An empty set leaves auth unconfigured
  /// for local templates; the Cloudflare template includes its D1 auth setup
  /// by default.
  final Set<String> authPlugins;

  /// JSON for the sample todo data used by starter templates.
  String get sampleTodosJson => jsonEncode(<Map<String, dynamic>>[
    {'id': 1, 'title': 'Ship Routed starter', 'completed': false},
  ]);

  /// Token replacements shared by generated files.
  ///
  /// These values are consumed by embedded scaffold sources; callers creating
  /// a custom [ScaffoldTemplate] may use the same keys for consistency.
  Map<String, String> get replacements => {
    '{{{routed:packageName}}}': packageName,
    '{{{routed:humanName}}}': humanName,
    '{{{routed:sampleTodosJson}}}': sampleTodosJson,
  };
}

/// A named scaffold template and the files it can render.
///
/// A template describes files relative to the generated project root and any
/// additional runtime or development dependencies needed by those files.
class ScaffoldTemplate {
  /// Creates a scaffold template with the supplied file builders.
  ScaffoldTemplate({
    required this.id,
    required this.description,
    required Map<String, FileBuilder> files,
    FileBuilder? readme,
    Map<String, String>? extraDependencies,
    Map<String, String>? extraDevDependencies,
  }) : fileBuilders = files,
       readmeBuilder = readme ?? _defaultReadme,
       extraDependencies = extraDependencies ?? const {},
       extraDevDependencies = extraDevDependencies ?? const {};

  /// Stable template identifier, such as `basic` or `fullstack`.
  final String id;

  /// Human-readable description of the template.
  final String description;

  /// Builders keyed by destination-relative file paths.
  final Map<String, FileBuilder> fileBuilders;

  /// Builder for the generated README.
  final FileBuilder readmeBuilder;

  /// Additional runtime dependencies required by this template.
  ///
  /// Values are pubspec constraint strings, such as `>=0.2.0 <1.0.0`.
  final Map<String, String> extraDependencies;

  /// Additional development dependencies required by this template.
  final Map<String, String> extraDevDependencies;

  /// Renders the template README for [context].
  String renderReadme(TemplateContext context) => readmeBuilder(context);
}

/// Registry and renderer for the built-in Routed scaffolds.
///
/// The available identifiers are `basic`, `api`, `web`, `fullstack`, and
/// `cloudflare`.
/// `CreateCommand` uses this registry to generate typed Dart configuration in
/// `lib/config.dart`; provider selection is code-owned rather than YAML-owned.
/// For example, the equivalent command-line workflow is:
///
/// ```text
/// routed create --name todo_app --template fullstack
/// cd todo_app
/// routed dev
/// routed deploy --target cloudflare
/// ```
class Templates {
  Templates._();

  static final Map<String, ScaffoldTemplate> _templates = {
    'basic': _buildTemplate(
      id: 'basic',
      description: 'Minimal JSON welcome route with typed provider setup.',
    ),
    'api': _buildTemplate(
      id: 'api',
      description: 'JSON-first API skeleton with sample routes and tests.',
      extraDependencies: const {
        'routed_http': '>=0.1.0 <1.0.0',
      },
      extraDevDependencies: const {
        'routed_testing': '>=0.4.0 <1.0.0',
        'server_testing': '^0.4.0',
      },
    ),
    'web': _buildTemplate(
      id: 'web',
      description: 'Server-rendered pages with HTML helpers.',
      extraDependencies: const {
        'routed_storage': '>=0.2.0 <1.0.0',
        'routed_views': '>=0.2.0 <1.0.0',
      },
    ),
    'fullstack': _buildTemplate(
      id: 'fullstack',
      description: 'Combined HTML + JSON starter, handy for SPAs or HTMX.',
      extraDependencies: const {
        'routed_http': '>=0.1.0 <1.0.0',
        'routed_views': '>=0.2.0 <1.0.0',
      },
      extraDevDependencies: const {
        'routed_testing': '>=0.4.0 <1.0.0',
        'server_testing': '^0.4.0',
      },
    ),
    'cloudflare': _buildTemplate(
      id: 'cloudflare',
      description:
          'Cloudflare Worker starter with D1, auth, and typed migrations.',
      extraDependencies: const {
        'routed_auth': '>=0.2.0 <1.0.0',
        'routed_auth_cloudflare': '>=0.1.1 <1.0.0',
        'routed_node': '>=0.2.1 <1.0.0',
        'routed_sessions': '>=0.2.1 <1.0.0',
        'server_auth': '>=0.2.0 <1.0.0',
      },
    ),
  };

  /// Resolves a built-in template by case-insensitive [id].
  ///
  /// Throws an [ArgumentError] when [id] is not one of the built-in
  /// identifiers.
  static ScaffoldTemplate resolve(String id) {
    final key = id.toLowerCase();
    final template = _templates[key];
    if (template == null) {
      throw ArgumentError('Unknown template "$id"');
    }
    return template;
  }

  /// Returns all built-in scaffold templates in registry order.
  static Iterable<ScaffoldTemplate> get all => _templates.values;

  /// Returns a concise, quoted description of the available template IDs.
  static String describe() =>
      all.map((template) => '"${template.id}"').join(', ');
}

ScaffoldTemplate _buildTemplate({
  required String id,
  required String description,
  Map<String, String>? extraDependencies,
  Map<String, String>? extraDevDependencies,
}) {
  final files = _buildFileBuilders(id);
  final readmeBuilder = _resolveReadme(id);
  return ScaffoldTemplate(
    id: id,
    description: description,
    files: files,
    readme: readmeBuilder,
    extraDependencies: {
      if (id != 'cloudflare') 'ormed_sqlite': '>=0.4.0 <1.0.0',
      'routed_core': '>=0.5.0 <1.0.0',
      'routed_database': '>=0.1.0 <1.0.0',
      ...?extraDependencies,
    },
    extraDevDependencies: extraDevDependencies,
  );
}

Map<String, FileBuilder> _buildFileBuilders(String templateId) {
  final sources = <String, String>{};

  for (final entry in scaffoldTemplateBytes.entries) {
    final path = entry.key;
    if (path.startsWith('common/')) {
      final dest = path.substring('common/'.length);
      sources[dest] = path;
    }
  }

  final templatePrefix = '$templateId/';
  for (final entry in scaffoldTemplateBytes.entries) {
    final path = entry.key;
    if (path.startsWith(templatePrefix)) {
      final dest = path.substring(templatePrefix.length);
      sources[dest] = path;
    }
  }

  final builders = sources.map(
    (dest, source) => MapEntry(dest, (TemplateContext context) {
      final rendered = _renderTemplateFile(source, context);
      return dest == 'lib/app.dart'
          ? _wireApplicationConfig(rendered, templateId: templateId)
          : rendered;
    }),
  );

  builders['lib/config.dart'] = (context) =>
      _renderConfigTemplate(context, templateId: templateId);
  return builders;
}

String _renderConfigTemplate(
  TemplateContext context, {
  required String templateId,
}) {
  final imports = <String>[
    "import 'package:routed_core/routed_core.dart';",
    "import 'package:routed_database/routed_database.dart';",
    if (templateId == 'cloudflare')
      "import 'package:routed_node/cloudflare.dart';",
    if (templateId == 'cloudflare') "import 'auth.dart';",
    if (templateId == 'cloudflare')
      "import 'package:routed_auth/routed_auth.dart';",
    if (templateId == 'cloudflare')
      "import 'package:routed_sessions/routed_sessions.dart';",
    "import 'database.dart';",
    if (context.authPlugins.isNotEmpty && templateId != 'cloudflare')
      "import 'package:routed_auth/routed_auth.dart' show RoutedAuthDeploymentBinding;",
    if (context.authPlugins.isNotEmpty && templateId != 'cloudflare')
      "import 'package:server_auth/server_auth.dart' show AuthDeploymentPresets, UsernamePlugin;",
    if (templateId == 'web')
      "import 'package:routed_storage/routed_storage.dart';",
    if (templateId == 'web' || templateId == 'fullstack')
      "import 'package:routed_views/routed_views.dart';",
  ];

  final optionalProviders = switch (templateId) {
    'web' =>
      '''
      RoutedStorageProvider(),
      ViewServiceProvider(
        RoutedViewConfig(directory: 'templates'),
      ),
      RoutedStaticProvider(
        StaticConfig(
          enabled: true,
          mounts: const [
            StaticMountConfig(route: '/assets', root: 'public'),
          ],
        ),
      ),''',
    'fullstack' =>
      '''
      ViewServiceProvider(
        RoutedViewConfig(directory: 'templates'),
      ),''',
    _ => '',
  };
  final hasUsername = context.authPlugins.contains('username');
  final hasLocalUsername = hasUsername && templateId != 'cloudflare';
  final authSetup = hasLocalUsername
      ? '''
  final auth = AuthDeploymentPresets.localDevelopment<EngineContext>(
    providers: const [],
    plugins: [UsernamePlugin<EngineContext>()],
    trustedOrigins: [Uri.parse('http://localhost:8080')],
  );
'''
      : '';
  final authProvider = hasLocalUsername
      ? '      auth.serviceProvider(),\n'
      : '';
  final authArguments = hasLocalUsername
      ? '''
    engineConfig: auth.engineConfig(),
    options: [auth.bindTo],
'''
      : '';

  final configDeclaration = templateId == 'cloudflare'
      ? 'Future<AppConfig> config(CloudflareEnvironment environment) async'
      : 'AppConfig config()';
  final databaseManager = templateId == 'cloudflare'
      ? 'createDatabaseManager(environment)'
      : 'createDatabaseManager()';
  final cloudflareAuthSetup = templateId == 'cloudflare'
      ? '  final auth = await createCloudflareAuthSetup(\n'
            '    environment,\n'
            '    includeUsername: ${hasUsername ? 'true' : 'false'},\n'
            '  );\n'
      : '';
  final cloudflareAuthProviders = templateId == 'cloudflare'
      ? '''      RoutedSessionsProvider(auth.sessions),
      auth.deployment.serviceProvider(),
'''
      : '';
  final cloudflareAuthArguments = templateId == 'cloudflare'
      ? '''    engineConfig: auth.deployment.engineConfig(),
    options: [auth.deployment.bindTo],
'''
      : '';

  return '''
${imports.join('\n')}

/// Typed application wiring shared by the runtime and Routed CLI flows.
///
/// Keep provider-owned configuration beside its provider constructor. Return
/// fresh instances because CLI inspection and deployment may build an engine
/// separately from the running server.
final class AppConfig {
  AppConfig({
    required Iterable<ServiceProvider> providers,
    this.engineConfig,
    RuntimeContext? runtime,
    Iterable<EngineOpt> options = const [],
  }) : providers = List<ServiceProvider>.unmodifiable(providers),
       runtime = runtime ?? RuntimeContext(),
       options = List<EngineOpt>.unmodifiable(options);

  final List<ServiceProvider> providers;
  final RuntimeContext runtime;
  final EngineConfig? engineConfig;
  final List<EngineOpt> options;

  Engine buildEngine() => Engine(
    config: engineConfig,
    runtime: runtime,
    providers: providers,
    options: options,
  );
}

$configDeclaration {
$authSetup$cloudflareAuthSetup  return AppConfig(
$cloudflareAuthArguments$authArguments
    providers: [
      CoreServiceProvider(),
      RoutingServiceProvider(),
      RoutedDatabaseProvider(
        manager: $databaseManager,
        migrations: appMigrations,
        migrateOnBoot: true,
      ),
$optionalProviders
$cloudflareAuthProviders
$authProvider    ],
  );
}
''';
}

String _wireApplicationConfig(String content, {required String templateId}) {
  if (templateId == 'cloudflare') {
    // The Cloudflare source owns its environment-aware provider composition;
    // only add the generated config import here. Replacing the side-effect
    // free local `createEngine` would incorrectly introduce a Worker
    // environment parameter into CLI route inspection.
    var source = content;
    if (!source.contains('package:routed_node/cli_provider.dart')) {
      source = source.replaceFirst(
        "import 'package:routed_node/cloudflare.dart';",
        "import 'package:routed_node/cloudflare.dart';\n"
            "import 'package:routed_node/cli_provider.dart';",
      );
    }
    if (!source.contains('...routedNodeCliProviders()')) {
      source = source.replaceFirst(
        '      RoutingServiceProvider(),',
        '      RoutingServiceProvider(),\n      ...routedNodeCliProviders(),',
      );
    }
    return "import 'config.dart';\n\n$source";
  }

  const configuredBlock = '''
  final setup = config();
  final engine = setup.buildEngine();''';

  final providerBlock = RegExp(
    r'  final engine = Engine\(\s*'
    r'providers:\s*\[\s*'
    r'CoreServiceProvider(?:\.withLoader)?\([\s\S]*?\),\s*'
    r'RoutingServiceProvider\(\),\s*'
    r'\],\s*'
    r'\);',
    multiLine: true,
  );

  if (!providerBlock.hasMatch(content)) {
    throw StateError(
      'The embedded app scaffold no longer contains the expected provider '
      'block. Update _wireApplicationConfig with the new template shape.',
    );
  }

  var source = content;
  if (templateId == 'api') {
    source = source.replaceFirst("import 'dart:io';\n\n", '');
  }

  var configured = "import 'config.dart';\n\n$source".replaceFirst(
    providerBlock,
    configuredBlock,
  );

  if (templateId == 'web' || templateId == 'fullstack') {
    configured = configured.replaceFirst(
      "  engine.useViewEngine(LiquidViewEngine(directory: 'templates'));\n\n",
      '',
    );
  }
  if (templateId == 'web') {
    configured = configured.replaceFirst(
      "import 'package:routed_storage/routed_storage.dart';\n",
      '',
    );
    configured = configured.replaceFirst(
      "  engine.static('/assets', 'public');\n\n",
      '',
    );
  }

  return configured;
}

FileBuilder _resolveReadme(String templateId) {
  final path = '$templateId/README.md';
  if (scaffoldTemplateBytes.containsKey(path)) {
    return (context) => _withTypedConfigGuide(
      _renderTemplateFile(path, context),
      templateId: templateId,
    );
  }
  return (context) =>
      _withTypedConfigGuide(_defaultReadme(context), templateId: templateId);
}

String _withTypedConfigGuide(String readme, {required String templateId}) {
  final selectedProviders = switch (templateId) {
    'web' =>
      'RoutedDatabaseProvider, ViewServiceProvider, '
          'RoutedStorageProvider, and RoutedStaticProvider',
    'fullstack' => 'RoutedDatabaseProvider and ViewServiceProvider',
    'cloudflare' => 'RoutedDatabaseProvider backed by Cloudflare D1',
    _ => 'RoutedDatabaseProvider plus the core and routing providers',
  };
  final databaseGuide = templateId == 'cloudflare'
      ? 'The generated lib/database.dart owns the Cloudflare D1 factory and '
            'codegen-free Ormed migrations; use ctx.db() from handlers.'
      : 'The generated lib/database.dart owns the SQLite factory and '
            'codegen-free Ormed migrations; use ctx.db() from handlers. '
            'For Cloudflare, replace the SQLite factory with openCloudflareD1 '
            'in an environment-aware engine.';
  final authGuide = templateId == 'cloudflare'
      ? 'The Cloudflare starter also composes routed_auth with a D1-backed '
            'credential store and secure cookie sessions; set AUTH_ORIGIN and '
            'SESSION_KEY before boot.'
      : 'Add auth server and client plugins only when the application uses '
            'them; the scaffold does not install optional auth behavior.';

  return '''
${readme.trimRight()}

## Typed application configuration

`lib/config.dart` is the single public composition point used by the server and
Routed CLI tooling. This template selects $selectedProviders. Add another
provider by importing its public package and constructing it there with its
typed configuration. $authGuide

Do not add YAML configuration or a driver registry. $databaseGuide Environment
values and secrets should be read by application code and passed into typed
constructors.
''';
}

String _defaultReadme(TemplateContext context) => '# ${context.humanName}\n';

String _renderTemplateFile(String sourcePath, TemplateContext context) {
  final bytes = scaffoldTemplateBytes[sourcePath];
  if (bytes == null) {
    throw ArgumentError('Template not found: $sourcePath');
  }
  var content = utf8.decode(bytes).replaceFirst(RegExp(r'\x00+$'), '');
  if (sourcePath.endsWith('/test/api_test.dart')) {
    content = content.replaceFirst("import 'package:test/test.dart';\n\n", '');
  }
  if (sourcePath == 'fullstack/lib/app.dart') {
    content = content.replaceFirst(
      '''
          () async => todos.firstWhere(
            (item) => item['id'].toString() == id,
            orElse: () => null,
          ),''',
      '''
          () async {
            for (final item in todos) {
              if (item['id'].toString() == id) return item;
            }
            return null;
          },''',
    );
  }
  return _applyReplacements(
    content,
    context.replacements,
  ).replaceAll('https://routed.dev', 'https://kingwill101.github.io/routed/');
}

String _applyReplacements(String content, Map<String, String> replacements) {
  var output = content;
  for (final entry in replacements.entries) {
    output = output.replaceAll(entry.key, entry.value);
  }
  return output;
}
