import 'dart:io';

/// Utility for matching IP addresses against CIDR ranges.
class NetworkMatcher {
  NetworkMatcher._(this._bytes, this._prefixLength);

  final List<int> _bytes;
  final int _prefixLength;

  /// Parses [value] as an IP or CIDR range. Returns `null` when parsing fails.
  static NetworkMatcher? maybeParse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parts = trimmed.split('/');
    final ipPart = parts.first.trim();
    if (ipPart.isEmpty) {
      return null;
    }
    final address = InternetAddress.tryParse(ipPart);
    if (address == null) {
      return null;
    }
    final bytes = address.rawAddress;
    final defaultPrefix = bytes.length == 4 ? 32 : 128;
    final prefix = parts.length > 1
        ? int.tryParse(parts[1].trim()) ?? defaultPrefix
        : defaultPrefix;
    final normalizedPrefix = prefix.clamp(0, defaultPrefix);
    return NetworkMatcher._(bytes, normalizedPrefix);
  }

  /// Parses [value] as an IP or CIDR range. Throws [FormatException] on failure.
  static NetworkMatcher parse(String value) {
    final matcher = maybeParse(value);
    if (matcher == null) {
      throw FormatException('Invalid CIDR or IP value "$value"');
    }
    return matcher;
  }

  /// Returns whether [address] falls inside this matcher.
  bool contains(InternetAddress address) {
    final target = address.rawAddress;
    if (target.length != _bytes.length) {
      return false;
    }
    var bitsRemaining = _prefixLength;
    for (var i = 0; i < _bytes.length && bitsRemaining > 0; i++) {
      final mask = bitsRemaining >= 8 ? 0xFF : _mask(bitsRemaining);
      if ((_bytes[i] & mask) != (target[i] & mask)) {
        return false;
      }
      bitsRemaining -= 8;
    }
    return true;
  }

  int _mask(int bits) {
    final shift = 8 - bits;
    return (0xFF << shift) & 0xFF;
  }
}
