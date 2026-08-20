## 0.1.0

- Generate typed SCIM Group collection/resource operations, direct-member
  request/response schemas, bearer security, protocol media types, status
  responses, and durable atomic-operation semantics.
- Publish strengthened organization atomic-operation and idempotent-replay
  semantics through the existing auth operation OpenAPI extension.
- Generate SAML metadata, sign-in, and ACS contracts with exact XML/form media
  types and durable atomic replay semantics.
- Preserve the Admin plugin's strengthened atomic command references,
  single-use impersonation transitions, and intentionally non-atomic external
  revocation boundaries in generated operation semantics.
- Preserve public auth persistence, atomicity, and replay semantics in the
  generated `x-routed-auth-operation-semantics` operation extension.
- Generate plugin-declared PUT, PATCH, DELETE, bearer-security, path-parameter,
  protocol media-type, and explicit status response contracts, including the
  opt-in SCIM 2.0 server surface.
- Generate the exact frozen opt-in auth topology, including host-owned routes,
  API-key and session security alternatives, client-safe operation IDs,
  generic public error schemas, and read-only one-time secret fields.
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
