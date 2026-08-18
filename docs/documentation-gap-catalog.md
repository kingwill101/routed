# Routed documentation gap catalog

Audit date: 2026-08-15

This catalog compares the public documentation, package READMEs, workspace
manifest, current exports, provider registry, and the recent host/runtime work.
It is intentionally focused on actionable drift rather than copy-editing.

## Status definitions

- **Confirmed stale**: the documented API, path, version, or behavior conflicts
  with the current checkout.
- **Missing coverage**: the implementation exists, but the docs site does not
  explain or expose it.
- **Decision needed**: the repository contains a reference, but ownership or
  package boundaries are no longer clear enough to decide whether to update or
  remove it.

## Prioritized findings

| ID | Priority | Area | Status | Evidence | Recommended action | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| DOC-001 | P0 | `Engine.serve` | Addressed | The engine examples used `address:` where the current `serve` API accepts `host:`. | Changed both examples to `host:`. `serveSecure` remains documented separately because it has a different signature. | Docs |
| DOC-002 | P0 | Built-in providers | Addressed | The current `ProviderRegistry` starts with three foundation registrations, and the `package:routed` barrel adds the official feature providers, including storage-backed static mounts. | `package:routed/routed.dart` re-exports the available split packages, `registerRoutedProviders()` is documented as the explicit bootstrap step, and the registry-count test protects the 15-provider bundle. `routed.security` covers request-size limits, trusted proxies, configurable CORS, and optional IP filtering; `routed.compression` covers opt-in gzip compression; `routed.static` covers declarative static mounts. | Routed + docs |
| DOC-008 | P0 | Declarative static mounts | Addressed | `routed_storage` now exports `RoutedStaticProvider`; it resolves storage-backed mounts, supports GET/HEAD, directory indexes/listings, and rebuilds routes on config reload. | Keep provider integration tests and the public static-assets/storage docs aligned as mount options evolve. | Routed + docs |
| DOC-003 | Addressed | `routed_testing` | Addressed | The site and package README now use the current `0.3.3` package line, current `server_testing`/`routed_core` dependencies, and the `engineTest` API. | Keep the examples covered by the package test suite when the testing API changes. | Docs/Testing |
| DOC-004 | Addressed | Pre-split source links | Addressed | The remaining Routed docs references were updated from `packages/routed/...` to the current `routed_core`, `routed_views`, `server_cache`, and `server_contracts` owners. | Add a repository-path existence check to the docs CI audit in DOC-014. | Docs |
| DOC-005 | P1 | CLI deployment | Addressed | `DeployCommand` supports Cloudflare, Netlify, and Vercel, including Vercel Node/Edge, generated bundles, provider CLI invocation, and dry-run options (`packages/routed_cli/lib/src/console/args/commands/deploy.dart:11-61`). | Added a deployment section covering prerequisites, target differences, generated artifacts, `--dry-run`, credentials/secrets, `--keep-vars`, compatibility dates, and recovery. | Docs |
| DOC-006 | P1 | Portable hosts | Addressed | The workspace includes `routed_io`, `routed_node`, and `server_native`, while the host architecture contract defines serve and fetch boundaries. `routed_node` provides Node, Bun, Deno, Cloudflare, Vercel, and Netlify entrypoints. | Added a maintained Host Runtimes guide with the runtime matrix, canonical imports, serve vs fetch examples, capability limitations, WebSocket support, and the separate `server_native` role. | Docs |
| DOC-007 | P1 | WebSockets | Addressed | The WebSocket handler is host-neutral, while the runtime adapters expose different upgrade capabilities. | Updated the guide with the host support matrix, portable `RoutedWebSocket` context, listener vs fetch behavior, and unsupported Vercel Edge/Netlify Edge cases. | Docs + Routed |
| DOC-009 | P1 | Getting-started install | Addressed | The guide imports `package:routed/routed.dart`, so `routed` is a runtime dependency. The CLI is a separate `routed_cli` package. | The guide now keeps `routed` in runtime dependencies, adds `routed_cli` and testing packages as dev dependencies, and uses `dart run routed_cli ...` consistently. | Docs |
| DOC-010 | P1 | Package/version catalog | Addressed | The root README previously listed only four local packages while the workspace declares the core, host, feature, OpenAPI, security, validation, native, and testing packages. | Added `docs/package-catalog.md` with current package versions, roles, links, and package-selection guidance; the root README now links to it. | Docs/release tooling |
| DOC-011 | P1 | Package README migration notes | Addressed | The package source already owns the view, translation, binding, negotiation, SSE, and conditional-request APIs. | Replaced migration language with public install instructions, current package responsibilities, and usage examples for `routed_views` and `routed_http`. | Docs/package owners |
| DOC-012 | P2 | Duplicate homepage | Addressed | The repository retains `docs/index.mdx` for historical reference while the active custom homepage is `docs/src/pages/index.tsx`. | Marked the legacy file explicitly as non-registered historical content so the active homepage remains the single site source of truth. | Docs |
| DOC-013 | P2 | OpenAPI command naming | Addressed | The runner supports the canonical `openapi:generate` command and normalizes the nested spelling for compatibility. | Site, package READMEs, examples, and CLI comments now invoke `dart run routed_cli`; the CLI page documents the canonical command and compatibility alias. | Docs/CLI |
| DOC-014 | P2 | Documentation verification | Partially addressed | Code examples are distributed across MDX and package READMEs, but there was no visible documentation audit. | Added `npm run audit` and a docs CI step that validates package catalog coverage/version parity and rejects internal-source or undefined package README examples. Compiling a curated set of Dart snippets remains a follow-up. | CI/docs |
| DOC-015 | P1 | Package README provider setup | Addressed | Several adapter READMEs used bare `Engine()` instances, undefined `router` examples, or did not explain whether the package registered a provider. | Updated provider-backed READMEs with `Engine.create`, explicit provider composition, and required middleware. Updated primitive/tooling READMEs to state that they do not register providers and point users to the correct Routed adapter or facade. | Docs/package owners |

## Already checked and currently aligned

These areas were checked during the audit and were not added as false-positive gaps:

- `routed_openapi` fluent route metadata and nested-group behavior match the
  current implementation and README (`packages/routed_openapi/README.md` and
  `docs/docs/routed/fundamentals/openapi-facilities.mdx`).
- `routed_hotwire` site installation currently matches its package version at
  `^0.1.2` (`docs/docs/routed_hotwire/index.mdx:19-24`).
- The `routed_node` package README documents the current multi-host entrypoint
  matrix; the gap is that the site does not expose or integrate that material,
  not that the README lacks the matrix.
- The docs site build and TypeScript checks pass after the recent site/theme
  work. Those checks do not validate Dart snippets or package/API parity, which
  is why DOC-014 remains open.

## Suggested execution order

1. Fix the directly broken examples and install instructions (DOC-001,
   DOC-003, DOC-009, DOC-013).
2. Add the host/deployment documentation (DOC-005, DOC-006, DOC-007) and update
   the root/package inventories (DOC-010, DOC-011).
3. Clean old source links and duplicate content (DOC-004, DOC-012), then add
   the verification checks in DOC-014.
