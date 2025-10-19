import 'dart:io';

import 'package:class_view/src/view/form/template_bundle.dart';
import 'package:class_view/src/view/form/widgets/widgets.dart';

/// Example demonstrating how to use the disk-loading FormTemplateBundle
Future<void> main() async {
  // Get the template bundle instance
  final templates = FormTemplateBundle.instance;

  print('🎨 Disk-Loading Template Bundle Example\n');

  // Example 1: Template statistics
  print('📊 Template Bundle Statistics:');
  final stats = templates.getStats();
  print('  Templates: ${stats['templateCount']}');
  print(
    '  Total Size: ${stats['totalBytes']} bytes (${_formatBytes(stats['totalBytes']!)})',
  );
  print('  Load from disk: ${stats['loadFromDisk']}');
  print('  Disk path: ${stats['diskPath']}');
  print('  Disk cache size: ${stats['diskCacheSize']}');
  print('');

  // Example 2: Bundle vs Disk loading comparison
  print('🔄 Bundle vs Disk Loading Comparison:');
  await demonstrateBundleVsDisk();
  print('');

  // Example 3: Access templates as bytes vs strings
  print('🔍 Async template access:');
  final textTemplatePath = 'widgets/text.liquid';
  final textBytes = await templates.getRequiredTemplateBytes(textTemplatePath);
  final textString = await templates.getRequiredTemplate(textTemplatePath);

  print('Template: $textTemplatePath');
  print('Bytes (${textBytes.length}): ${textBytes.take(20).toList()}...');
  print('String: "$textString"');
  print('');

  // Example 4: Use convenience getters (async)
  print('🎯 Using async convenience getters:');
  final emailWidget = await templates.emailWidget;
  print('Email widget (string): "$emailWidget"');

  final emailBytes = await templates.emailWidgetBytes;
  print('Email widget (bytes): ${emailBytes?.length} bytes');
  print('');

  // Example 5: Template existence and error handling
  print('✅ Template existence checks:');
  print(
    'widgets/text.liquid exists: ${await templates.hasTemplate('widgets/text.liquid')}',
  );
  print(
    'widgets/nonexistent.liquid exists: ${await templates.hasTemplate('widgets/nonexistent.liquid')}',
  );
  print('');

  // Example 6: Custom template demonstration
  print('📝 Custom template from disk demonstration:');
  await demonstrateCustomTemplate();
  print('');

  // Example 7: Performance comparison
  print('⚡ Performance benefits:');
  await demonstratePerformance();
  print('');

  // Example 8: Widget integration example
  print('🔗 Widget integration example:');
  await demonstrateWidgetIntegration();
}

/// Demonstrates bundle vs disk loading
Future<void> demonstrateBundleVsDisk() async {
  final templates = FormTemplateBundle.instance;

  print('  📦 Bundle mode (default):');
  final bundleTemplate = await templates.getTemplate('widgets/text.liquid');
  print('    Template: "$bundleTemplate"');

  // Enable disk loading
  templates.setLoadFromDisk(true);
  print('  💾 Disk mode enabled:');
  print('    Loading from: ${templates.diskTemplatesPath}');
  final diskTemplate = await templates.getTemplate('widgets/text.liquid');
  print('    Template: "$diskTemplate"');

  // Check if they're the same
  print('    Same content: ${bundleTemplate == diskTemplate}');

  // Disable disk loading
  templates.setLoadFromDisk(false);
  print('  📦 Back to bundle mode');
}

/// Demonstrates creating and loading a custom template
Future<void> demonstrateCustomTemplate() async {
  final templates = FormTemplateBundle.instance;

  // Create a custom template on disk
  final customTemplatePath = 'widgets/custom.liquid';
  final customTemplateFile = File(
    '${templates.diskTemplatesPath}/$customTemplatePath',
  );

  await customTemplateFile.parent.create(recursive: true);
  await customTemplateFile.writeAsString(
    '{% render "input", widget: widget %} <!-- Custom template -->',
  );

  print('  📄 Created custom template: $customTemplatePath');

  // Enable disk loading and try to load it
  templates.setLoadFromDisk(true);

  final customTemplate = await templates.getTemplate(customTemplatePath);
  if (customTemplate != null) {
    print('  ✅ Successfully loaded custom template: "$customTemplate"');
  } else {
    print('  ❌ Failed to load custom template');
  }

  print('  📊 Disk cache size: ${templates.getStats()['diskCacheSize']}');

  // Clean up
  if (await customTemplateFile.exists()) {
    await customTemplateFile.delete();
    print('  🗑️  Cleaned up custom template');
  }

  templates.clearDiskCache();
  templates.setLoadFromDisk(false);
}

/// Demonstrates performance benefits of byte storage
Future<void> demonstratePerformance() async {
  final templates = FormTemplateBundle.instance;

  // Test bundle performance (synchronous)
  print('  📦 Bundle performance (sync):');
  final bundleStopwatch = Stopwatch()..start();

  for (int i = 0; i < 1000; i++) {
    final bytes = templates.getTemplateBytesSync('widgets/text.liquid');
    if (bytes != null) {
      templates.getTemplateSync('widgets/text.liquid');
    }
  }

  bundleStopwatch.stop();
  print('    • 1000 sync accesses: ${bundleStopwatch.elapsedMicroseconds}μs');

  // Test async performance
  print('  🔄 Async performance:');
  final asyncStopwatch = Stopwatch()..start();

  for (int i = 0; i < 100; i++) {
    final bytes = await templates.getTemplateBytes('widgets/text.liquid');
    if (bytes != null) {
      await templates.getTemplate('widgets/text.liquid');
    }
  }

  asyncStopwatch.stop();
  print('    • 100 async accesses: ${asyncStopwatch.elapsedMicroseconds}μs');

  print(
    '  💡 Use sync methods for best performance when disk loading is disabled',
  );
  print(
    '  💡 Use async methods when disk loading is enabled for customization',
  );
}

/// Demonstrates how to integrate the template bundle with widgets
Future<void> demonstrateWidgetIntegration() async {
  final templates = FormTemplateBundle.instance;

  // Create a text input widget
  final textWidget = TextInput(
    attrs: {'class': 'form-control', 'placeholder': 'Enter text'},
  );

  // Get the template as bytes (most efficient)
  final templateBytes = await templates.getRequiredTemplateBytes(
    'widgets/text.liquid',
  );
  print('Template bytes for TextInput: ${templateBytes.length} bytes');

  // Get the template as string when needed for rendering
  final templateString = await templates.getRequiredTemplate(
    'widgets/text.liquid',
  );
  print('Template string: "$templateString"');

  // Example widget context (what would be passed to the template)
  final context = textWidget.getContext('username', 'john_doe');
  print('\n📝 Widget context:');
  print(context);

  print('\n💡 Best practices:');
  print('1. Use sync methods when possible for performance');
  print('2. Enable disk loading for development/customization');
  print('3. Cache templates when rendering multiple times');
  print('4. Use byte storage for efficient memory usage');
}

/// Example of a performance-optimized template renderer with disk support
class OptimizedTemplateRenderer {
  final FormTemplateBundle _templates = FormTemplateBundle.instance;
  final Map<String, String> _stringCache = {};

  /// Enable development mode with disk loading
  void enableDevelopmentMode({String? templatesPath}) {
    _templates.setLoadFromDisk(true, templatesPath: templatesPath);
    clearCache(); // Clear cache when switching modes
  }

  /// Enable production mode with bundle loading
  void enableProductionMode() {
    _templates.setLoadFromDisk(false);
    clearCache();
  }

  /// Render a widget using the bundled templates with caching
  Future<String> renderWidget(
    Widget widget,
    String templatePath,
    Map<String, dynamic> context,
  ) async {
    // Get cached string template or load/decode from source
    String template;
    if (_stringCache.containsKey(templatePath)) {
      template = _stringCache[templatePath]!;
    } else {
      template = await _templates.getRequiredTemplate(templatePath);
      _stringCache[templatePath] = template;
    }

    // In a real implementation, you would use a liquid template engine
    return '''
Template: $template
Context: $context
Size: ${await _templates.getTemplateSize(templatePath)} bytes
Source: ${_templates.isLoadingFromDisk ? 'disk' : 'bundle'}
''';
  }

  /// Get widget template path with type safety
  String? getWidgetTemplatePath(Widget widget) {
    final templateMap = {
      TextInput: 'widgets/text.liquid',
      EmailInput: 'widgets/email.liquid',
      PasswordInput: 'widgets/password.liquid',
      NumberInput: 'widgets/number.liquid',
      Textarea: 'widgets/textarea.liquid',
    };

    return templateMap[widget.runtimeType];
  }

  /// Clear the string cache to free memory
  void clearCache() {
    _stringCache.clear();
    _templates.clearDiskCache();
  }

  /// Get comprehensive renderer statistics
  Map<String, dynamic> getStats() {
    final bundleStats = _templates.getStats();
    return {
      ...bundleStats,
      'rendererCacheSize': _stringCache.length,
      'mode': _templates.isLoadingFromDisk ? 'development' : 'production',
    };
  }
}

/// Format bytes into human readable format
String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
