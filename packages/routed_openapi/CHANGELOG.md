## 0.1.0

- Add `package:routed_openapi/server_auth.dart` and
  `AuthServerPluginRegistry.toOpenApi31(...)` for generating OpenAPI 3.1
  documents directly from the composed auth plugin registry.
- Generate stable operation IDs, plugin tags, typed request/response schemas,
  path/query parameters, cookie/bearer security, CSRF headers, standard error
  responses, and root `/.well-known/` operations; reject duplicate paths and
  operation IDs.
- Clarified that runtime request validation is opt-in and separate from
  OpenAPI generation.
- Updated the OpenAPI workflow and examples to use the current CLI command and
  route metadata APIs.
- Initial package scaffold for the routed modular package split.
