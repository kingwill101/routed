import '../template_manager.dart';
import '../view_engine.dart';
import 'renderer.dart';

/// Framework-agnostic Template implementation following Django's pattern
///
/// Stores template name and ViewEngine reference, provides caching,
/// and handles both sync/async rendering like Django's Template class.
class ViewEngineTemplate extends Template {
  final String templateName;
  final ViewEngine? _viewEngine;
  final bool _enableCaching;

  // Cache for rendered results (like Django's compiled nodelist concept)
  String? _cachedResult;
  Map<String, dynamic>? _cachedContext;

  ViewEngineTemplate(
    this.templateName,
    this._viewEngine, {
    bool enableCaching = false,
  }) : _enableCaching = enableCaching;

  /// Synchronous render method (Django interface compatibility)
  ///
  /// Since Dart ViewEngines are async, this throws with helpful guidance.
  /// In Django, this would use the compiled nodelist to render synchronously.
  @override
  String render(Map<String, dynamic> context, [dynamic extra1]) {
    throw UnsupportedError(
      'Template.render() is synchronous but liquid templates require async rendering. '
      'Use TemplateRenderer.renderAsync() or Template.renderAsync() instead.',
    );
  }

  /// Async render method (the one that actually works)
  ///
  /// This is like Django's render() but async. Handles optional caching
  /// of rendered results for performance.
  Future<String> renderAsync(Map<String, dynamic> context) async {
    // Check cache if enabled (simple context-based caching)
    if (_enableCaching && _cachedResult != null && _contextMatches(context)) {
      return _cachedResult!;
    }

    // Render using ViewEngine if available
    String result;
    if (_viewEngine != null) {
      try {
        result = await _viewEngine.render(templateName, context);
      } catch (e, stackTrace) {
        if (e is TemplateNotFoundException) {
          rethrow;
        }
        // Handle rendering errors gracefully, perhaps logging them
        print('Error rendering template "$templateName": $e');
        print('Stack trace: $stackTrace');
        // Optionally rethrow, or return a default error message
        result = 'Error rendering template: $templateName';
      }
    } else {
      // If no ViewEngine is configured, throw an informative error
      throw StateError(
        'TemplateRenderer is configured without a ViewEngine. '
        'Please provide a ViewEngine to TemplateRenderer or initialize TemplateManager.',
      );
    }

    // Cache result if enabled
    if (_enableCaching) {
      _cachedResult = result;
      _cachedContext = Map.from(context);
    }

    return result;
  }

  /// Check if context matches cached context (simple equality check)
  bool _contextMatches(Map<String, dynamic> context) {
    if (_cachedContext == null) return false;
    if (_cachedContext!.length != context.length) return false;

    for (final entry in context.entries) {
      if (_cachedContext![entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Clear cached results (useful for testing or dynamic templates)
  void clearCache() {
    _cachedResult = null;
    _cachedContext = null;
  }

  /// Template name getter (like Django's Template.name)
  String get name => templateName;

  /// Check if template has cached results
  bool get isCached => _cachedResult != null;
}

/// Template renderer that uses a provided ViewEngine or falls back to TemplateManager
///
/// This bridges the existing Renderer interface with ViewEngine systems,
/// providing seamless integration with forms and widgets.
class TemplateRenderer extends Renderer {
  final ViewEngine? _viewEngine;
  final bool _enableTemplateCache;
  final Map<String, ViewEngineTemplate> _templateCache = {};

  TemplateRenderer({
    ViewEngine? viewEngine,
    bool enableTemplateCache = true,
    super.formTemplateName = 'form/form_div.html',
    super.formsetTemplateName = 'form/formsets/div.html',
    super.fieldTemplateName = 'forms/field.html',
  }) : _viewEngine = viewEngine,
       _enableTemplateCache = enableTemplateCache;

  @override
  Template getTemplate(String templateName) {
    // Return cached Template object if available (Django pattern)
    if (_enableTemplateCache && _templateCache.containsKey(templateName)) {
      return _templateCache[templateName]!;
    }

    // Create new Template object (like Django's template compilation)
    final template = ViewEngineTemplate(
      templateName,
      _viewEngine,
      enableCaching: _enableTemplateCache,
    );

    // Cache the Template object itself (like Django's template loader caching)
    if (_enableTemplateCache) {
      _templateCache[templateName] = template;
    }

    return template;
  }

  @override
  Future<String> renderAsync(
    String templateName,
    Map<String, dynamic> context,
  ) async {
    if (_viewEngine == null) {
      // If no ViewEngine is provided, attempt to use the default from TemplateManager
      // This requires TemplateManager to be initialized with a ViewEngine first.
      if (TemplateManager.engine == null) {
        throw StateError(
          'TemplateManager has no ViewEngine configured. Please initialize it.',
        );
      }
      // Use the global ViewEngine if available
      final globalEngine = TemplateManager.engine!;
      final template = ViewEngineTemplate(
        templateName,
        globalEngine,
        enableCaching: _enableTemplateCache,
      );
      return await template.renderAsync(context);
    }

    // If ViewEngine is provided directly to the renderer, use it
    final template =
        getTemplate(templateName)
            as ViewEngineTemplate; // Cast to ViewEngineTemplate
    return await template.renderAsync(context);
  }

  /// Clear all template caches
  void clearCache() {
    for (final template in _templateCache.values) {
      template.clearCache();
    }
    _templateCache.clear();
  }

  /// Get cached template names
  List<String> get cachedTemplateNames => _templateCache.keys.toList();
}
