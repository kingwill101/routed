# Routed Examples

This directory contains examples demonstrating the usage of the Routed web framework. Most examples are single Dart
files for easy exploration. Complex examples with assets, templates, or configuration remain as directories.

## Single-File Examples

Run any example with: `dart <filename>.dart`

- **basic_router.dart** - Basic routing functionality including path parameters, query strings, and request body
  handling
- **binding.dart** - JSON, form URL encoded, query, and multipart form data binding
- **caching.dart** - Response caching examples
- **constraint_validation.dart** - Route parameter constraints
- **cookie.dart** - Cookie handling basics
- **cookie_handling.dart** - Advanced cookie management with attributes
- **engine_config.dart** - Engine configuration options (trailing slash, method not allowed, IP forwarding)
- **engine_default_router.dart** - Registering routes directly on the engine with middleware
- **engine_route.dart** - Routes with various parameter types (integer, double, slug, UUID, email, IP, string)
- **error_handling.dart** - Global and route-level error handling
- **file_serve.dart** - Static file serving
- **form_widgets.dart** - Form handling examples
- **forward_proxy.dart** - Basic forward proxy functionality
- **group.dart** - Route grouping with middleware
- **haigate.dart** - Haigate gates combined with session auth and guard middleware
- **jwt_auth.dart** - JWT bearer authentication and IP filtering
- **multipart_validation.dart** - Multipart form validation with file uploads
- **query.dart** - Query parameter handling
- **query_parameter.dart** - Query parameter validation
- **route_grouping.dart** - Advanced route grouping patterns
- **route_matching.dart** - Route matching for different HTTP methods
- **route_parameter_types.dart** - Parameter type handling in routes
- **signals.dart** - Demonstrates the SignalHub request lifecycle hooks and error propagation
- **session_auth_guard.dart** - Session-based authentication with remember-me tokens
- **sessions.dart** - Session management
- **sse_counter.dart** - Server-Sent Events streaming
- **static_file_example.dart** - Static file serving examples
- **static_file_serving_example.dart** - Static files with directory listing
- **template_engine_example.dart** - Template rendering (Jinja/Liquid)
- **timeout_middleware_example.dart** - Request timeout handling
- **validation.dart** - Request data validation rules
- **validation_example.dart** - Advanced validation patterns- **view_shortcuts.dart** - Shows how to use `ctx.requireFound` and `ctx.fetchOr404` to raise 404s when data is missing

## Directory Examples

These examples require additional assets, configuration, or complex project structure:

- **config_demo/** - Comprehensive configuration system demo with YAML configs
- **fallback/** - Fallback route handling with public assets
- **forward_proxy/** - Complete forward proxy server with documentation
- **http2/** - HTTP/2 examples with TLS certificates
- **kitchen_sink/** - Full-featured application demo with templates, public assets, and lib structure
- **liquid_template/** - Liquid template engine with template files
- **multipart/** - Multipart form handling with template files
- **oauth_keycloak/** - OAuth integration with Keycloak (Docker setup included)
- **route_events/** - Route lifecycle events with lib structure
- **view_engine/** - View engine integration with view templates
- **websocket_chat/** - WebSocket chat application with public assets

Each directory example contains its own README with specific setup instructions.- **view_shortcuts.dart** - Shows how to use `ctx.requireFound` and `ctx.fetchOr404` to raise 404s when data is missing
- **view_shortcuts.dart** - Shows how to use `ctx.requireFound` and `ctx.fetchOr404` to raise 404s when data is missing
