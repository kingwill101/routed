/// Analyzer plugin entry point for the routed framework.
///
/// This plugin provides IDE linting for route definitions, catching common
/// issues like missing schema metadata, undocumented responses, and invalid
/// validation rules.
///
/// ## Activation
///
/// Add `routed` to the `plugins` list in your `analysis_options.yaml`:
///
/// ```yaml
/// analyzer:
///   plugins:
///     - routed
/// ```
library;

import 'package:routed_analyzer/routed_analyzer.dart';

/// The analyzer plugin instance discovered by the analysis server.
final plugin = RoutedAnalyzerPlugin();
