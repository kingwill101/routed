/// Represents a semantic version number, typically in major.minor.patch format.
///
/// Provides parsing from strings and comparison logic implementing [Comparable].
class Version implements Comparable<Version> {
  /// The numeric components of the version number (e.g., `[1, 2, 3]` for "1.2.3").
  final List<int> parts;

  /// Creates a constant [Version] instance directly from a list of integer [parts].
  const Version(this.parts);

  /// Parses a version string into a [Version] object.
  ///
  /// Splits the [version] string by non-digit characters (like '.', '-', '+')
  /// and converts the resulting parts to integers. Handles common formats like
  /// `1.2.3`, `114.0.5735.90`, `v0.36.0`.
  ///
  /// Throws a [FormatException] if the input string is empty or contains no digits.
  factory Version.parse(String version) {
    // Split on dots and any non-numeric characters
    final parts = version
        .split(RegExp(r'[^\d]+'))
        .where((part) => part.isNotEmpty)
        .map(int.parse)
        .toList();

    if (parts.isEmpty) {
      throw FormatException('Invalid version format: $version');
    }

    return Version(parts);
  }

  /// Compares this version to [other] based on their numeric parts.
  ///
  /// Compares parts from left to right. If one version has more parts than
  /// the other, missing parts are treated as 0. Returns -1, 0, or 1.
  @override
  int compareTo(Version other) {
    final maxLength =
        parts.length > other.parts.length ? parts.length : other.parts.length;

    for (var i = 0; i < maxLength; i++) {
      final thisPart = i < parts.length ? parts[i] : 0;
      final otherPart = i < other.parts.length ? other.parts[i] : 0;

      final comparison = thisPart.compareTo(otherPart);
      if (comparison != 0) return comparison;
    }

    return 0;
  }

  /// Returns the standard dot-separated string representation of the version.
  @override
  String toString() => parts.join('.');

  /// Checks if this version is equal to [other].
  ///
  /// Compares based on the string representation.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Version && toString() == other.toString();

      /// The hash code based on the string representation.
  @override
  int get hashCode => toString().hashCode;

  /// Whether this version is greater than [other].
  bool operator >(Version other) => compareTo(other) > 0;
  /// Whether this version is less than [other].
  bool operator <(Version other) => compareTo(other) < 0;
  /// Whether this version is greater than or equal to [other].
  bool operator >=(Version other) => compareTo(other) >= 0;
  /// Whether this version is less than or equal to [other].
  bool operator <=(Version other) => compareTo(other) <= 0;

  /// The major version number (the first part). Returns 0 if no parts exist.
  int get major => parts.isNotEmpty ? parts[0] : 0;
  /// The minor version number (the second part). Returns 0 if fewer than 2 parts exist.
  int get minor => parts.length > 1 ? parts[1] : 0;
  /// The patch version number (the third part). Returns 0 if fewer than 3 parts exist.
  int get patch => parts.length > 2 ? parts[2] : 0;
}
