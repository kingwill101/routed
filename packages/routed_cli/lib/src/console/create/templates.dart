import 'dart:convert';

import 'package:routed_cli/src/console/create/templates_embedded.dart';

typedef FileBuilder = String Function(TemplateContext context);

class TemplateContext {
  TemplateContext({required this.packageName, required this.humanName});

  final String packageName;
  final String humanName;

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
    ),
    'fullstack': _buildTemplate(
      id: 'fullstack',
      description: 'Combined HTML + JSON starter, handy for SPAs or HTMX.',
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
    extraDependencies: extraDependencies,
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
          ? _wireApplicationConfig(rendered)
          : rendered;
    }),
  );

  builders['lib/config.dart'] = _renderConfigTemplate;
  return builders;
}

String _renderConfigTemplate(TemplateContext context) => '''
import 'package:routed/routed.dart';

/// Typed application wiring shared by the runtime and Routed CLI flows.
///
/// Return fresh provider instances here. The CLI may construct a separate
/// engine for route inspection, OpenAPI generation, or deployment.
final class AppConfig {
  AppConfig({
    required Iterable<ServiceProvider> providers,
    RuntimeContext? runtime,
  }) : providers = List<ServiceProvider>.unmodifiable(providers),
       runtime = runtime ?? RuntimeContext();

  final List<ServiceProvider> providers;
  final RuntimeContext runtime;
}

AppConfig config() => AppConfig(
  providers: [
    CoreServiceProvider(),
    RoutingServiceProvider(),
  ],
);
''';

String _wireApplicationConfig(String content) {
  const configuredBlock = '''  final setup = config();
  final engine = Engine(
    runtime: setup.runtime,
    providers: setup.providers,
  );''';

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

  return "import 'config.dart';\n\n$content".replaceFirst(
    providerBlock,
    configuredBlock,
  );
}

FileBuilder _resolveReadme(String templateId) {
  final path = '$templateId/README.md';
  if (scaffoldTemplateBytes.containsKey(path)) {
    return (context) => _renderTemplateFile(path, context);
  }
  return _defaultReadme;
}

String _defaultReadme(TemplateContext context) => '# ${context.humanName}\n';

String _renderTemplateFile(String sourcePath, TemplateContext context) {
  final bytes = scaffoldTemplateBytes[sourcePath];
  if (bytes == null) {
    throw ArgumentError('Template not found: $sourcePath');
  }
  final content = utf8.decode(bytes);
  return _applyReplacements(content, context.replacements);
}

String _applyReplacements(String content, Map<String, String> replacements) {
  var output = content;
  for (final entry in replacements.entries) {
    output = output.replaceAll(entry.key, entry.value);
  }
  return output;
}
