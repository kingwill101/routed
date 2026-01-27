library;

import 'templates.dart';

/// Defines scaffold templates for supported frontend frameworks.
///
/// ```dart
/// final framework = InertiaFramework.parse('react');
/// ```
///
/// Configuration for a supported Inertia frontend framework.
class InertiaFramework {
  /// Creates a framework configuration.
  const InertiaFramework({
    required this.key,
    required this.label,
    required this.viteTemplate,
    required this.dependencies,
    required this.mainFile,
    required this.ssrFile,
    required this.pageFile,
    required this.configTemplate,
    required this.mainTemplate,
    required this.ssrTemplate,
    required this.pageTemplate,
  });

  /// Machine-friendly key used in CLI arguments.
  final String key;

  /// Human-readable label for output.
  final String label;

  /// Vite template name.
  final String viteTemplate;

  /// Package dependencies for the framework adapter.
  final List<String> dependencies;

  /// Main entry file path.
  final String mainFile;

  /// SSR entry file path.
  final String ssrFile;

  /// Initial page file path.
  final String pageFile;

  /// Vite config template content.
  final String configTemplate;

  /// Main entry template content.
  final String mainTemplate;

  /// SSR entry template content.
  final String ssrTemplate;

  /// Page template content.
  final String pageTemplate;

  /// React framework configuration.
  static const react = InertiaFramework(
    key: 'react',
    label: 'React',
    viteTemplate: 'react',
    dependencies: ['@inertiajs/react'],
    mainFile: 'src/main.jsx',
    ssrFile: 'src/ssr.jsx',
    pageFile: 'src/Pages/Home.jsx',
    configTemplate: inertiaReactConfig,
    mainTemplate: inertiaReactMain,
    ssrTemplate: inertiaReactSsr,
    pageTemplate: inertiaReactPage,
  );

  /// Vue framework configuration.
  static const vue = InertiaFramework(
    key: 'vue',
    label: 'Vue',
    viteTemplate: 'vue',
    dependencies: ['@inertiajs/vue3', '@vue/server-renderer'],
    mainFile: 'src/main.js',
    ssrFile: 'src/ssr.js',
    pageFile: 'src/Pages/Home.vue',
    configTemplate: inertiaVueConfig,
    mainTemplate: inertiaVueMain,
    ssrTemplate: inertiaVueSsr,
    pageTemplate: inertiaVuePage,
  );

  /// Svelte framework configuration.
  static const svelte = InertiaFramework(
    key: 'svelte',
    label: 'Svelte',
    viteTemplate: 'svelte',
    dependencies: ['@inertiajs/svelte'],
    mainFile: 'src/main.js',
    ssrFile: 'src/ssr.js',
    pageFile: 'src/Pages/Home.svelte',
    configTemplate: inertiaSvelteConfig,
    mainTemplate: inertiaSvelteMain,
    ssrTemplate: inertiaSvelteSsr,
    pageTemplate: inertiaSveltePage,
  );

  /// Parses [value] into a supported framework configuration.
  static InertiaFramework parse(String? value) {
    switch (value) {
      case 'vue':
        return vue;
      case 'svelte':
        return svelte;
      case 'react':
      default:
        return react;
    }
  }
}
