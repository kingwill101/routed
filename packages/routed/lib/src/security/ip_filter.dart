import 'dart:io';

import 'package:routed/src/security/network.dart';

/// Defines the default behaviour when no allow/deny rule matches.
enum IpFilterAction { allow, deny }

class IpFilter {
  const IpFilter({
    required this.enabled,
    required this.defaultAction,
    required this.allow,
    required this.deny,
    required this.respectTrustedProxies,
  });

  factory IpFilter.disabled() => const IpFilter(
    enabled: false,
    defaultAction: IpFilterAction.allow,
    allow: <NetworkMatcher>[],
    deny: <NetworkMatcher>[],
    respectTrustedProxies: true,
  );

  final bool enabled;
  final IpFilterAction defaultAction;
  final List<NetworkMatcher> allow;
  final List<NetworkMatcher> deny;
  final bool respectTrustedProxies;

  bool allows(String ip) {
    if (!enabled) {
      return true;
    }
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null) {
      return defaultAction == IpFilterAction.allow;
    }
    for (final matcher in deny) {
      if (matcher.contains(parsed)) {
        return false;
      }
    }
    for (final matcher in allow) {
      if (matcher.contains(parsed)) {
        return true;
      }
    }
    return defaultAction == IpFilterAction.allow;
  }
}
