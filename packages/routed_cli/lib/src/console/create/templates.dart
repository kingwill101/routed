import 'dart:convert';

import 'package:routed_cli/src/console/create/templates_embedded.dart';

typedef FileBuilder = String Function(TemplateContext context);

class TemplateContext {
  TemplateContext({
    required this.packageName,
    required this.humanName,
    Iterable<String> authPlugins = const [],
  }) : authPlugins = Set<String>.unmodifiable(authPlugins);

  final String packageName;
  final String humanName;
  final Set<String> authPlugins;

  String get sampleTodosJson => jsonEncode(<Map<String, dynamic>>[
    {'id': 1, 'title': 'Ship Routed starter', 'completed': false},
  ]);

  Map<String, String> get replacements => {
    '{{{routed:packageName}}}': packageName,
    '{{{routed:humanName}}}': humanName,
    '{{{routed:sampleTodosJson}}}': sampleTodosJson,
  };
}

class ScaffoldTemplate {
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

  final String id;
  final String description;
  final Map<String, FileBuilder> fileBuilders;
  final FileBuilder readmeBuilder;
  final Map<String, String> extraDependencies;
  final Map<String, String> extraDevDependencies;

  String renderReadme(TemplateContext context) => readmeBuilder(context);
}

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
      extraDependencies: const {'routed_views': '>=0.2.0 <1.0.0'},
      extraDevDependencies: const {
        'routed_testing': '>=0.4.0 <1.0.0',
        'server_testing': '^0.4.0',
      },
    ),
  };

  static ScaffoldTemplate resolve(String id) {
    final key = id.toLowerCase();
    final template = _templates[key];
    if (template == null) {
      throw ArgumentError('Unknown template "$id"');
    }
    return template;
  }

  static Iterable<ScaffoldTemplate> get all => _templates.values;

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
    extraDependencies: {'routed_core': '>=0.5.0 <1.0.0', ...?extraDependencies},
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
    if (context.authPlugins.isNotEmpty)
      "import 'package:routed_auth/routed_auth.dart' "
          'show RoutedAuthDeploymentBinding;',
    if (context.authPlugins.isNotEmpty)
      "import 'package:server_auth/server_auth.dart' "
          'show AuthDeploymentPresets, UsernamePlugin;',
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
  final authSetup = hasUsername
      ? '''
  final auth = AuthDeploymentPresets.localDevelopment<EngineContext>(
    providers: const [],
    plugins: [UsernamePlugin<EngineContext>()],
    trustedOrigins: [Uri.parse('http://localhost:8080')],
  );
'''
      : '';
  final authProvider = hasUsername ? '      auth.serviceProvider(),\n' : '';
  final authArguments = hasUsername
      ? '''    engineConfig: auth.engineConfig(),
    options: [auth.bindTo],
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

AppConfig config() {
$authSetup  return AppConfig(
    providers: [
      CoreServiceProvider(),
      RoutingServiceProvider(),
$optionalProviders
$authProvider    ],
$authArguments  );
}
''';
}

String _wireApplicationConfig(String content, {required String templateId}) {
  const configuredBlock = '''  final setup = config();
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
      '`ViewServiceProvider`, `RoutedStorageProvider`, and '
          '`RoutedStaticProvider`',
    'fullstack' => '`ViewServiceProvider`',
    _ => 'only the core and routing providers',
  };

  return '''
${readme.trimRight()}

## Typed application configuration

`lib/config.dart` is the single public composition point used by the server and
Routed CLI tooling. This template selects $selectedProviders. Add another
provider by importing its public package and constructing it there with its
typed configuration. Add auth server and client plugins only when the
application uses them; the scaffold does not install optional auth behavior.

Do not add YAML configuration or a driver registry. Environment values and
secrets should be read by application code and passed into typed constructors.
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
      '''          () async => todos.firstWhere(
            (item) => item['id'].toString() == id,
            orElse: () => null,
          ),''',
      '''          () async {
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
