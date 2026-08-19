/// A host-neutral parsed IP address.
///
/// Unlike `dart:io`'s [InternetAddress], this value can be parsed and matched
/// on runtimes that do not provide socket APIs, including Fetch workers.
final class IpAddress {
  IpAddress._(List<int> bytes) : bytes = List<int>.unmodifiable(bytes);

  /// The address bytes in network order.
  ///
  /// IPv4 addresses contain four bytes and IPv6 addresses contain sixteen.
  final List<int> bytes;

  /// Whether this is an IPv4 address.
  bool get isIpv4 => bytes.length == 4;

  /// Parses an IPv4 or IPv6 address without performing DNS lookups.
  static IpAddress? tryParse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains('%')) return null;

    final ipv4 = _parseIpv4(trimmed);
    if (ipv4 != null) return IpAddress._(ipv4);
    if (!trimmed.contains(':')) return null;

    final compression = trimmed.indexOf('::');
    if (compression != -1 && compression != trimmed.lastIndexOf('::')) {
      return null;
    }

    final hasCompression = compression != -1;
    final left = hasCompression ? trimmed.substring(0, compression) : trimmed;
    final right = hasCompression ? trimmed.substring(compression + 2) : '';
    final leftGroups = _parseIpv6Groups(left, allowIpv4: !hasCompression);
    final rightGroups = _parseIpv6Groups(right, allowIpv4: true);
    if (leftGroups == null || rightGroups == null) return null;

    final groupCount = leftGroups.length + rightGroups.length;
    if (hasCompression) {
      if (groupCount >= 8) return null;
    } else if (groupCount != 8) {
      return null;
    }

    final groups = <int>[
      ...leftGroups,
      if (hasCompression) ...List<int>.filled(8 - groupCount, 0),
      ...rightGroups,
    ];
    final bytes = <int>[];
    for (final group in groups) {
      bytes
        ..add((group >> 8) & 0xFF)
        ..add(group & 0xFF);
    }
    return IpAddress._(bytes);
  }

  static List<int>? _parseIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return null;
    final bytes = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return null;
      for (var i = 0; i < part.length; i++) {
        final code = part.codeUnitAt(i);
        if (code < 0x30 || code > 0x39) return null;
      }
      final byte = int.tryParse(part);
      if (byte == null || byte > 255) return null;
      bytes.add(byte);
    }
    return bytes;
  }

  static List<int>? _parseIpv6Groups(String value, {required bool allowIpv4}) {
    if (value.isEmpty) return <int>[];
    final parts = value.split(':');
    final groups = <int>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) return null;
      if (part.contains('.')) {
        if (!allowIpv4 || i != parts.length - 1) return null;
        final ipv4 = _parseIpv4(part);
        if (ipv4 == null) return null;
        groups
          ..add((ipv4[0] << 8) | ipv4[1])
          ..add((ipv4[2] << 8) | ipv4[3]);
        continue;
      }
      if (part.length > 4) return null;
      var group = 0;
      for (var j = 0; j < part.length; j++) {
        final code = part.codeUnitAt(j);
        final digit = switch (code) {
          >= 0x30 && <= 0x39 => code - 0x30,
          >= 0x41 && <= 0x46 => code - 0x41 + 10,
          >= 0x61 && <= 0x66 => code - 0x61 + 10,
          _ => -1,
        };
        if (digit < 0) return null;
        group = (group << 4) | digit;
      }
      groups.add(group);
    }
    return groups;
  }
}
