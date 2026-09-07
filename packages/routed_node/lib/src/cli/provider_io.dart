import 'package:routed_core/routed_core.dart';

import 'provider.dart';

/// Returns routed_node CLI providers on Dart VM hosts.
Iterable<ServiceProvider> routedNodeCliProviders() => <ServiceProvider>[
  RoutedNodeCliProvider(),
];
