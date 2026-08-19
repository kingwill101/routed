# routed_security

Security providers and primitives for Routed integrations: CORS, IP
filtering, network matching, trusted-proxy resolution, and request-size
configuration. Security headers and CSRF remain explicit middleware or
application concerns.

## Install
```yaml
dependencies:
  routed: ^0.4.0
  routed_security: ^0.1.0
```

## Initialize security in a Routed app

```dart
import 'package:routed/routed.dart';

Future<void> main() async {
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      RoutedSecurityProvider(
        RoutedSecurityConfig(
          maxRequestSize: 5 * 1024 * 1024,
          cors: CorsConfig(
            enabled: true,
            allowedOrigins: ['https://app.example'],
            allowedMethods: ['GET', 'POST'],
            allowedHeaders: ['Authorization', 'Content-Type'],
          ),
          trustedProxies: TrustedProxyConfig(
            enabled: true,
            proxies: ['10.0.0.0/8'],
          ),
          ipFilter: IpFilterConfig(
            enabled: true,
            deny: ['203.0.113.0/24'],
          ),
        ),
      ),
    ],
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
  final engine = await Engine.create(
    providers: [
      ...Engine.defaultProviders,
      RoutedSecurityProvider(
        RoutedSecurityConfig(
          cors: CorsConfig(
            enabled: true,
            allowedOrigins: ['https://app.example'],
            allowedMethods: ['GET', 'POST'],
            allowedHeaders: ['Authorization', 'Content-Type'],
          ),
          trustedProxies: TrustedProxyConfig(
            enabled: true,
            proxies: ['10.0.0.0/8'],
          ),
          ipFilter: IpFilterConfig(
            enabled: true,
            deny: ['203.0.113.0/24'],
          ),
        ),
      ),
    ],
  );
  await engine.serve(port: 8080);
}
```

When `cors.enabled` is true, the provider adds response headers for allowed
origins and handles `OPTIONS` preflight requests. Keep credentialed requests
on an explicit origin allow-list; wildcard origins are echoed per request when
credentials are enabled because browsers reject `*` with credentials.

The security provider validates all network and header values before any
provider boots. Configuration is typed and fixed for the lifetime of the
engine; create a new provider/engine for a different policy. If you only need
a primitive such as `TrustedProxyResolver`, use it directly without
registering a provider. Enabling trusted-proxy support also requires at least
one explicit proxy network; Routed never defaults to trusting all forwarded
addresses.
