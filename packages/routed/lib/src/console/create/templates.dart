import 'dart:convert';

import 'package:routed/src/console/create/templates_embedded.dart';

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
      description: 'Minimal JSON welcome route and config files.',
    ),
    'api': _buildTemplate(
      id: 'api',
      description: 'JSON-first API skeleton with sample routes and tests.',
      extraDevDependencies: const {
        'routed_testing': '^0.2.1',
        'server_testing': '^0.3.0',
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
        'routed_testing': '^0.2.1',
        'server_testing': '^0.3.0',
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

  return sources.map(
    (dest, source) =>
        MapEntry(dest, (context) => _renderTemplateFile(source, context)),
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
