import 'dart:io';

import 'package:liquify/liquify.dart' hide TemplateNotFoundException;

import '../template_manager.dart';
import '../view_engine.dart';

/// Liquify template engine implementation
///
/// Provides full Liquid template support with:
/// - File system template resolution
/// - Layout inheritance via {% layout "base.liquid" %}
/// - Custom filters and tags
/// - Template caching for performance
/// - Graceful error handling
class LiquifyViewEngine implements ViewEngine {
  final Root _root;
  final Map<String, Template> _templateCache = {};
  final bool _cacheTemplates;

  LiquifyViewEngine({
    Root? root,
    bool cacheTemplates = true,
    String templateDirectory = 'templates',
  }) : _root = root ?? _createSafeFileSystemRoot(templateDirectory),
       _cacheTemplates = cacheTemplates;

  /// Create a LiquifyViewEngine with in-memory templates.
  ///
  /// Useful for default templates and testing:
  /// final engine = LiquifyViewEngine.memory({
  ///   'form.liquid': {@literal '<form>{{ form_content }}</form>'},
  ///   'field.liquid': {@literal '<div class="field">{{ field_content }}</div>'},
  /// });
  LiquifyViewEngine.memory(
    Map<String, String> templates, {
    bool cacheTemplates = true,
  }) : _root = MapRoot(templates),
       _cacheTemplates = cacheTemplates;

  /// Create a LiquifyViewEngine with memory-only templates (no filesystem access)
  ///
  /// Alias for memory constructor with more descriptive naming:
  /// final engine = LiquifyViewEngine.memoryOnly(
  ///   templates: {'form.html': {@literal '<form>{{ form_content }}</form>'}},
  ///   cacheTemplates: true,
  /// );
  LiquifyViewEngine.memoryOnly({
    required Map<String, String> templates,
    bool cacheTemplates = true,
  }) : _root = MapRoot(templates),
       _cacheTemplates = cacheTemplates;

  /// Create a LiquifyViewEngine with combined memory and file system roots
  ///
  /// Checks memory templates first, then falls back to file system:
  /// ```dart
  /// final engine = LiquifyViewEngine.combined(
  ///   memoryTemplates: {'layout.liquid': '...'},
  ///   templateDirectory: 'templates',
  /// );
  /// ```
  LiquifyViewEngine.combined({
    Map<String, String>? memoryTemplates,
    String templateDirectory = 'templates',
    bool cacheTemplates = true,
  }) : _root = _createCombinedRoot(memoryTemplates, templateDirectory),
       _cacheTemplates = cacheTemplates;

  static Root _createCombinedRoot(
    Map<String, String>? memoryTemplates,
    String templateDirectory,
  ) {
    final roots = <Root>[];

    // Add memory root first (higher priority)
    if (memoryTemplates != null && memoryTemplates.isNotEmpty) {
      roots.add(MapRoot(memoryTemplates));
    }

    // Add file system root as fallback
    roots.add(FileSystemRoot(templateDirectory, throwOnMissing: true));

    return roots.length == 1 ? roots.first : CombinedRoot(roots);
  }

  /// Create a FileSystemRoot safely, with fallback to memory-only
  static Root _createSafeFileSystemRoot(String templateDirectory) {
    try {
      // Check if directory exists
      final dir = Directory(templateDirectory);
      if (!dir.existsSync()) {
        print(
          'Warning: Template directory "$templateDirectory" does not exist. Using memory-only templates.',
        );
        return MapRoot(DefaultTemplates.createTemplateMap());
      }

      return FileSystemRoot(templateDirectory, throwOnMissing: true);
    } catch (e) {
      print(
        'Warning: Failed to create FileSystemRoot for "$templateDirectory": $e. Using memory-only templates.',
      );
      return MapRoot(DefaultTemplates.createTemplateMap());
    }
  }

  @override
  List<String> get extensions => ['.liquid', '.html'];

  @override
  Future<String> render(
    String templateName, [
    Map<String, dynamic>? data,
  ]) async {
    if (!await templateExists(templateName)) {
      throw TemplateNotFoundException(templateName);
    }
    try {
      final template = await _getTemplate(templateName);
      if (data != null) {
        template.updateContext(data);
      }
      final result = await template.renderAsync();
      return result;
    } on TemplateNotFoundException {
      rethrow;
    } catch (e, stackTrace) {
      // Handle other errors gracefully
      print('Error rendering template "$templateName": $e');
      print('Stack trace: $stackTrace');
      return '';
    }
  }

  @override
  Future<String> renderFile(
    String filePath, [
    Map<String, dynamic>? data,
  ]) async {
    return render(filePath, data);
  }

  /// Get or create a template with caching
  Future<Template> _getTemplate(String templateName) async {
    if (_cacheTemplates && _templateCache.containsKey(templateName)) {
      return _templateCache[templateName]!;
    }

    final template = Template.fromFile(templateName, _root);

    if (_cacheTemplates) {
      _templateCache[templateName] = template;
    }

    return template;
  }

  /// Clear template cache
  void clearCache() {
    _templateCache.clear();
  }

  /// Check if template exists
  Future<bool> templateExists(String templateName) async {
    try {
      final source = await _root.resolveAsync(templateName);
      return source.content.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get the underlying Root for advanced usage
  Root get root => _root;
}

/// Combined root that checks multiple roots in order
///
/// This allows checking memory templates first, then file system templates
class CombinedRoot extends Root {
  final List<Root> _roots;

  CombinedRoot(this._roots);

  /// Get all roots in search order
  List<Root> get roots => List.unmodifiable(_roots);

  @override
  Source resolve(String relPath) {
    for (final root in _roots) {
      final source = root.resolve(relPath);
      if (source.content.isNotEmpty) return source;
    }
    // Use the first root to create an empty source
    return _roots.first.resolve('__not_found__');
  }

  @override
  Future<Source> resolveAsync(String relPath) async {
    for (final root in _roots) {
      final source = await root.resolveAsync(relPath);
      if (source.content.isNotEmpty) {
        return source;
      }
    }
    // Use the first root to create an empty source
    return _roots.first.resolveAsync('__not_found__');
  }

  /// Add a root to the beginning of the search order
  void prependRoot(Root root) {
    _roots.insert(0, root);
  }

  /// Add a root to the end of the search order
  void appendRoot(Root root) {
    _roots.add(root);
  }
}
