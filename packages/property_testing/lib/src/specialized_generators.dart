import 'dart:math' as math;

import 'generator_base.dart';
import 'generators/color_generator.dart';
import 'generators/datetime_generator.dart';
import 'generators/duration_generator.dart';
import 'generators/email_generator.dart';
import 'generators/semver_generator.dart';
import 'generators/uri_generator.dart';

// Re-export all generator classes
export 'generators/color_generator.dart';
export 'generators/datetime_generator.dart';
export 'generators/duration_generator.dart';
export 'generators/email_generator.dart';
export 'generators/semver_generator.dart';
export 'generators/uri_generator.dart';

/// A collection of specialized generators for common data types
class Specialized {
  /// Generate DateTime values
  static Generator<DateTime> dateTime({
    DateTime? min,
    DateTime? max,
    bool utc = false,
  }) =>
      DateTimeGenerator(min: min, max: max, utc: utc);

  /// Generate Duration values
  static Generator<Duration> duration({
    Duration? min,
    Duration? max,
  }) =>
      DurationGenerator(min: min, max: max);

  /// Generate URI values
  static Generator<Uri> uri({
    List<String>? schemes,
    bool includeUserInfo = false,
    bool includeFragment = true,
    bool includeQueryParameters = true,
    int maxPathSegments = 5,
    int maxQueryParameters = 5,
  }) =>
      UriGenerator(
        schemes: schemes,
        includeUserInfo: includeUserInfo,
        includeFragment: includeFragment,
        includeQueryParameters: includeQueryParameters,
        maxPathSegments: maxPathSegments,
        maxQueryParameters: maxQueryParameters,
      );

  /// Generate email addresses
  static Generator<String> email({
    List<String>? domains,
    int maxLocalPartLength = 64,
  }) =>
      EmailGenerator(
        domains: domains,
        maxLocalPartLength: maxLocalPartLength,
      );

  /// Generate semantic version strings
  static Generator<String> semver({
    bool prerelease = true,
    bool build = true,
  }) =>
      SemverGenerator(
        prerelease: prerelease,
        build: build,
      );

  /// Generate color values
  static Generator<Color> color({
    bool alpha = false,
  }) =>
      ColorGenerator(includeAlpha: alpha);
}
