# routed_security

Security providers and primitives for Routed integrations: CORS, IP
filtering, network matching, trusted-proxy resolution, and request-size
configuration. Security headers and CSRF remain explicit middleware or
application concerns.

## Install
```yaml
dependencies:
  routed: ^0.3.3
  routed_security: ^0.1.0
```

## Initialize security in a Routed app

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  registerRoutedProviders();
  final engine = await Engine.create(
    configItems: {
      'cors': {
        'enabled': true,
        'allowed_origins': ['https://app.example'],
        'allowed_methods': ['GET', 'POST'],
        'allowed_headers': ['Authorization', 'Content-Type'],
      },
      'security': {
        'max_request_size': 5 * 1024 * 1024,
        'trusted_proxies': {
          'enabled': true,
          'proxies': ['10.0.0.0/8'],
        },
        'ip_filter': {
          'enabled': true,
          'deny': ['203.0.113.0/24'],
        },
      },
    },
  );

  await engine.serve(port: 8080);
}
```

For a slim composition, import this package and register the provider before
creating the engine:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_security/routed_security.dart';

Future<void> main() async {
  registerRoutedSecurityProviders();
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      RoutedSecurityProvider(),
    ],
  );
  await engine.serve(port: 8080);
}
```

When `cors.enabled` is true, the provider adds response headers for allowed
origins and handles `OPTIONS` preflight requests. Keep credentialed requests
on an explicit origin allow-list; wildcard origins are echoed per request when
credentials are enabled because browsers reject `*` with credentials.

Call `registerRoutedProviders()` before `Engine.create()` when using the
batteries-included facade, or call `registerRoutedSecurityProviders()` when
you compose the security package directly. If you only need a primitive such
as `TrustedProxyResolver`, import and use it directly without registering a
provider.
