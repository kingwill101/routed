import 'package:class_view/class_view.dart';
import 'package:class_view/src/view/engines/liquify_view_engine.dart';

/// Example demonstrating the new renderer-neutral TemplateManager
///
/// This example shows how to:
/// 1. Initialize TemplateManager with different ViewEngines
/// 2. Use TemplateManager without explicit initialization (will fail gracefully)
/// 3. Configure TemplateManager for different use cases
void main() async {
  print('=== Renderer-Neutral TemplateManager Example ===\n');

  // Example 1: TemplateManager without initialization (will fail gracefully)
  print('1. TemplateManager without initialization:');
  try {
    await TemplateManager.render('test.html', {'message': 'Hello'});
  } catch (e) {
    print('   ✅ Expected error: $e');
  }
  print('');

  // Example 2: Initialize with memory-only templates (for testing)
  print('2. Initialize with memory-only templates:');
  TemplateManager.configureMemoryOnly(
    extraTemplates: {
      'custom/test.html': '''
        <div class="custom">
          <h1>{{ title }}</h1>
          <p>{{ message }}</p>
        </div>
      ''',
    },
  );

  try {
    final result = await TemplateManager.render('custom/test.html', {
      'title': 'Custom Template',
      'message': 'This works!',
    });
    print('   ✅ Rendered successfully:');
    print('   $result');
  } catch (e) {
    print('   ❌ Unexpected error: $e');
  }
  print('');

  // Example 3: Reset and initialize with custom ViewEngine
  print('3. Initialize with custom ViewEngine:');
  TemplateManager.reset();

  // Create a custom ViewEngine (simplified example)
  final customEngine = LiquifyViewEngine.memoryOnly(
    templates: {
      'custom/engine.html': '''
        <div class="custom-engine">
          <h2>{{ title }}</h2>
          <p>{{ content }}</p>
        </div>
      ''',
    },
  );

  TemplateManager.initialize(customEngine);

  try {
    final result = await TemplateManager.render('custom/engine.html', {
      'title': 'Custom Engine',
      'content': 'Using custom ViewEngine!',
    });
    print('   ✅ Rendered with custom engine:');
    print('   $result');
  } catch (e) {
    print('   ❌ Unexpected error: $e');
  }
  print('');

  // Example 4: Configure with file-based templates
  print('4. Configure with file-based templates:');
  TemplateManager.reset();

  TemplateManager.configure(
    templateDirectory: 'templates',
    extraTemplates: {
      'configured/test.html': '''
        <div class="configured">
          <h3>{{ title }}</h3>
          <p>{{ message }}</p>
        </div>
      ''',
    },
    cacheTemplates: true,
  );

  try {
    final result = await TemplateManager.render('configured/test.html', {
      'title': 'Configured Template',
      'message': 'Using configure() method!',
    });
    print('   ✅ Rendered with configure():');
    print('   $result');
  } catch (e) {
    print('   ❌ Unexpected error: $e');
  }
  print('');

  // Example 5: TemplateRenderer with explicit ViewEngine
  print('5. TemplateRenderer with explicit ViewEngine:');
  final renderer = TemplateRenderer(
    viewEngine: LiquifyViewEngine.memoryOnly(
      templates: {
        'renderer/test.html': '''
          <div class="renderer">
            <h4>{{ title }}</h4>
            <p>{{ message }}</p>
          </div>
        ''',
      },
    ),
  );

  try {
    final result = await renderer.renderAsync('renderer/test.html', {
      'title': 'Renderer Template',
      'message': 'Using TemplateRenderer directly!',
    });
    print('   ✅ Rendered with TemplateRenderer:');
    print('   $result');
  } catch (e) {
    print('   ❌ Unexpected error: $e');
  }
  print('');

  // Example 6: TemplateRenderer without ViewEngine (falls back to TemplateManager)
  print('6. TemplateRenderer without ViewEngine (fallback):');
  final fallbackRenderer = TemplateRenderer();

  try {
    final result = await fallbackRenderer.renderAsync('configured/test.html', {
      'title': 'Fallback Template',
      'message': 'Using fallback to TemplateManager!',
    });
    print('   ✅ Rendered with fallback:');
    print('   $result');
  } catch (e) {
    print('   ❌ Unexpected error: $e');
  }
  print('');

  // Example 7: TemplateRenderer without ViewEngine and no TemplateManager
  print('7. TemplateRenderer without ViewEngine and no TemplateManager:');
  TemplateManager.reset(); // Clear TemplateManager
  final noEngineRenderer = TemplateRenderer();

  try {
    await noEngineRenderer.renderAsync('test.html', {'message': 'Hello'});
  } catch (e) {
    print('   ✅ Expected error: $e');
  }
  print('');

  print('=== Example Complete ===');
  print('\nKey Benefits:');
  print('✅ TemplateManager is now renderer-neutral');
  print('✅ No hardcoded dependency on LiquifyViewEngine');
  print('✅ Explicit initialization required for template rendering');
  print('✅ Graceful error handling when no ViewEngine is configured');
  print('✅ Support for custom ViewEngine implementations');
  print('✅ Fallback mechanism in TemplateRenderer');
}
