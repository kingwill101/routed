/// IP allow and deny primitives for Routed applications.
library;

import 'package:routed_core/routed_core.dart' show NetworkMatcher;

/// Defines the default behaviour when no allow/deny rule matches.
///
/// If no rules match, the [IpFilterAction.allow] permits the IP, while
/// [IpFilterAction.deny] blocks it.
enum IpFilterAction {
  /// Allows an address when no rule matches it.
  allow,

  /// Denies an address when no rule matches it.
  deny,
}

/// A filter for controlling access based on IP addresses.
///
/// [IpFilter] evaluates an address against an ordered deny list and allow list.
/// Deny rules take precedence, followed by allow rules, and then
/// [defaultAction]. The [respectTrustedProxies] value is available to callers
/// composing the filter with request middleware; [allows] itself evaluates
/// only the address passed to it.
///
/// Example usage:
/// ```dart
/// final filter = IpFilter(
///   enabled: true,
///   defaultAction: IpFilterAction.deny,
///   allow: [NetworkMatcher.parse('192.168.1.0/24')],
///   deny: [NetworkMatcher.parse('192.168.1.100')],
///   respectTrustedProxies: true,
/// );
///
/// print(filter.allows('192.168.1.50')); // true
/// print(filter.allows('192.168.1.100')); // false
/// print(filter.allows('10.0.0.1')); // false
/// ```
class IpFilter {
  /// Creates an [IpFilter] with the specified configuration.
  ///
  /// - [enabled]: Whether the filter is active.
  /// - [defaultAction]: The action to take when no rules match.
  /// - [allow]: A list of [NetworkMatcher]s specifying allowed IPs or ranges.
  /// - [deny]: A list of [NetworkMatcher]s specifying denied IPs or ranges.
  /// - [respectTrustedProxies]: Whether to respect trusted proxies when
  ///   evaluating IPs.
  const IpFilter({
    required this.enabled,
    required this.defaultAction,
    required this.allow,
    required this.deny,
    required this.respectTrustedProxies,
  });

  /// Creates a disabled [IpFilter] with default settings.
  ///
  /// Example:
  /// ```dart
  /// final filter = IpFilter.disabled();
  /// print(filter.allows('192.168.1.1')); // true
  /// ```
  factory IpFilter.disabled() => const IpFilter(
    enabled: false,
    defaultAction: IpFilterAction.allow,
    allow: <NetworkMatcher>[],
    deny: <NetworkMatcher>[],
    respectTrustedProxies: true,
  );

  /// Whether the filter is active.
  final bool enabled;

  /// The default action to take when no rules match.
  final IpFilterAction defaultAction;

  /// A list of [NetworkMatcher]s specifying allowed IPs or ranges.
  final List<NetworkMatcher> allow;

  /// A list of [NetworkMatcher]s specifying denied IPs or ranges.
  final List<NetworkMatcher> deny;

  /// Whether to respect trusted proxies when evaluating IPs.
  final bool respectTrustedProxies;

  /// Determines whether the given [ip] is allowed.
  ///
  /// - Returns `true` if the [ip] is allowed based on the rules.
  /// - Returns `false` if the [ip] is denied based on the rules.
  /// If [ip] is invalid or no rule matches, [defaultAction] is used.
  ///
  /// Example:
  /// ```dart
  /// final filter = IpFilter(
  ///   enabled: true,
  ///   defaultAction: IpFilterAction.deny,
  ///   allow: [NetworkMatcher.parse('10.0.0.0/8')],
  ///   deny: [NetworkMatcher.parse('10.0.0.5')],
  ///   respectTrustedProxies: false,
  /// );
  ///
  /// print(filter.allows('10.0.0.1')); // true
  /// print(filter.allows('10.0.0.5')); // false
  /// print(filter.allows('192.168.1.1')); // false
  /// ```
  bool allows(String ip) {
    if (!enabled) {
      return true;
    }
    for (final matcher in deny) {
      if (matcher.containsText(ip)) {
        return false;
      }
    }
    for (final matcher in allow) {
      if (matcher.containsText(ip)) {
        return true;
      }
    }
    return defaultAction == IpFilterAction.allow;
  }
}
