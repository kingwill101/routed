/// Analyzer plugin entry point for Routed analyzer rules.
///
/// This library is loaded by the Dart analysis server when
/// `routed_analyzer` is enabled in a package's top-level
/// `analysis_options.yaml`. Applications should import
/// `package:routed_analyzer/routed_analyzer.dart` for the public inspection
/// APIs instead of importing this entry point.
library;

import 'package:routed_analyzer/routed_analyzer.dart';

/// Analyzer plugin instance discovered by the analysis server.
final plugin = RoutedAnalyzerPlugin();
