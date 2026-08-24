import 'dart:io';

import 'package:routed_core/src/security/ip_address.dart';

/// Utility for matching IP addresses against CIDR ranges.
///
/// This class provides functionality to parse and match IP addresses
/// against CIDR ranges. It supports both IPv4 and IPv6 addresses.
///
/// Example usage:
/// ```dart
/// final matcher = NetworkMatcher.parse('192.168.1.0/24');
/// final address = InternetAddress('192.168.1.5');
/// print(matcher.contains(address)); // true
/// ```
class NetworkMatcher {
  NetworkMatcher._(this._bytes, this._prefixLength);

  final List<int> _bytes;
  final int _prefixLength;

  /// Parses [value] as an IP or CIDR range. Returns `null` when parsing fails.
  ///
  /// Example usage:
  /// ```dart
  /// final matcher = NetworkMatcher.maybeParse('10.0.0.0/8');
  /// if (matcher != null) {
  ///   print('Parsed successfully!');
  /// } else {
  ///   print('Invalid CIDR or IP value.');
  /// }
  /// ```
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
    final address = IpAddress.tryParse(ipPart);
    if (address == null) {
      return null;
    }
    final bytes = address.bytes;
    final defaultPrefix = bytes.length == 4 ? 32 : 128;
    final prefix = parts.length > 1
        ? int.tryParse(parts[1].trim()) ?? defaultPrefix
        : defaultPrefix;
    final normalizedPrefix = prefix.clamp(0, defaultPrefix);
    return NetworkMatcher._(bytes, normalizedPrefix);
  }

  /// Parses [value] as an IP or CIDR range. Throws [FormatException] on failure.
  ///
  /// Example usage:
  /// ```dart
  /// try {
  ///   final matcher = NetworkMatcher.parse('2001:db8::/32');
  ///   print('Parsed successfully!');
  /// } catch (e) {
  ///   print('Error: $e');
  /// }
  /// ```
  static NetworkMatcher parse(String value) {
    final matcher = maybeParse(value);
    if (matcher == null) {
      throw FormatException('Invalid CIDR or IP value "$value"');
    }
    return matcher;
  }

  /// Returns whether [address] falls inside this matcher.
  ///
  /// Example usage:
  /// ```dart
  /// final matcher = NetworkMatcher.parse('192.168.1.0/24');
  /// final address = InternetAddress('192.168.1.100');
  /// print(matcher.contains(address)); // true
  /// ```
  bool contains(InternetAddress address) {
    final target = _targetBytes(address.rawAddress);
    return _containsBytes(target);
  }

  /// Returns whether the textual [address] falls inside this matcher.
  ///
  /// This is the portable counterpart to [contains]. It does not use DNS or
  /// `dart:io`, so it is safe to call from Fetch and other worker runtimes.
  bool containsText(String address) {
    final parsed = IpAddress.tryParse(address);
    if (parsed == null) return false;
    return _containsBytes(_targetBytes(parsed.bytes));
  }

  List<int> _targetBytes(List<int> target) {
    if (_bytes.length == 4 && _isIpv4Mapped(target)) {
      return target.sublist(12);
    }
    return target;
  }

  bool _containsBytes(List<int> target) {
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

  static bool _isIpv4Mapped(List<int> bytes) {
    if (bytes.length != 16) return false;
    for (var i = 0; i < 10; i++) {
      if (bytes[i] != 0) return false;
    }
    return bytes[10] == 0xFF && bytes[11] == 0xFF;
  }

  int _mask(int bits) {
    final shift = 8 - bits;
    return (0xFF << shift) & 0xFF;
  }
}
