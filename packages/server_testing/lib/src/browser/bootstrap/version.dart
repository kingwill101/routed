class Version implements Comparable<Version> {
  final List<int> parts;

  const Version(this.parts);

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

  @override
  String toString() => parts.join('.');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Version && toString() == other.toString();

  @override
  int get hashCode => toString().hashCode;

  bool operator >(Version other) => compareTo(other) > 0;
  bool operator <(Version other) => compareTo(other) < 0;
  bool operator >=(Version other) => compareTo(other) >= 0;
  bool operator <=(Version other) => compareTo(other) <= 0;

  int get major => parts.isNotEmpty ? parts[0] : 0;
  int get minor => parts.length > 1 ? parts[1] : 0;
  int get patch => parts.length > 2 ? parts[2] : 0;
}
