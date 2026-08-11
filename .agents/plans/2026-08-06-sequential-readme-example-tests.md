## Goal
Restore each of the final 14 `routed_*` packages (plus `server_*` runtimes) to have a real README, example, and tests by re-using the tests that existed before the slim move, sequentially per package.

## Success Criteria
- Each package in final set has: README.md with purpose/usage, example/ that runs via `dart run`, and test/ that passes via `dart test` and covers pre-move behavior.
- Tests are the original tests moved in `a5d240d1 test: move routed tests to adapter packages` and `303ff6ea` etc., not new stubs — imported from `git show` history, updated to `package:server_*`/`package:routed_*` imports.
- `dart analyze --fatal-infos packages/<pkg>/lib` and `dart test packages/<pkg>` pass per package in sequential order.
- No empty `src/*` barrel re-exports remain; routed foundation stays `Engine/EngineContext/Request/Response/Router` only.

## Context And Current Facts
- Foundation slim done: `routed` is Engine/Context/Request/Response/Router; `routed/src/cache`, `context/cache.dart` moved to `server_cache`/`routed_cache` (verified `DataCacheManager` move, `ctx.json` helper restored, `cacheStore` rename). `routed_storage`/`routed_rate_limit` now wired to `server_storage`/`server_rate_limit` (`dart analyze` 0).
- Current package state (observed `ls`):
  - README exists only for 12/17 routed_* (missing `routed_config`, `routed_openapi`, `routed_openapi_builder`, `routed_sessions`? actually `routed_sessions` has, `routed_validation` missing, `routed_analyzer` has minimal). `routed_cache` README is 1 line stub.
  - example/ exists only for `routed`, `routed_auth` (oauth), `routed_hotwire`, `routed_openapi`. 10+ packages have no example.
  - test/ exists for `routed_cache` (cache_extended + stub provider), `routed_auth`, `routed_cli`, `routed_http`, but `routed_storage` test is broken (`file_handler` missing, `test_engine` missing), `routed_rate_limit` has no tests, `routed_views`/`routed_sessions` minimal, `routed_validation` has stray tests.
- Pre-move tests available via `a5d240d1`, `303ff6ea`, `76ee6551` etc.: e.g. `packages/routed/test/provider/cache_provider_test.dart`, `engine/middleware_cache_test.dart`, `events/cache_event_test.dart`, `static_files_test.dart`, `binding_test.dart`, `sse_test.dart`, `auth/*`, `localization_*`, `view/*`. Those commits moved copies to `routed_cli/test`, `routed_http/test`, `routed_view/test`, `server_cache/test`, `server_sessions/test`, `server_storage/test`.
- User constraint: move not change implementation, no barrel fallbacks, workspace-aware imports, atomic commits via `git add -p` and `gh stack`, staged-not-committed.

## Constraints And Non-goals
- Do not re-introduce `routed` barrel re-exports of `routed_*`/`server_*`; break intentionally.
- Do not change implementation while moving tests — only import path fixes (`routed/src/*` -> `server_*`/`routed_*`, `test_engine.dart`/`test_helpers.dart` copies).
- Non-goal: not fixing unrelated `file_handler` static file stack now beyond wiring tests that depend on it — those tests stay with `server_storage`/`server_native` where file_handler will live.

## Key Decisions
- Order sequentially by dependency: 1 `routed_cache` (already wired, easiest to finish), 2 `routed_sessions` (`server_sessions`), 3 `routed_storage` (`server_storage`), 4 `routed_auth` (`server_auth`), 5 `routed_http` (binding/multipart/sse), 6 `routed_views`, 7 `routed_validation`, 8 `routed_rate_limit`, 9 `routed_analyzer`/`routed_cli`/`routed_openapi`/`routed_openapi_builder`/`routed_io`/`routed_config`/`routed`.
- For each package: restore tests from `git show <commit>:<path>` (primary `a5d240d1`, fallback `303ff6ea`/`HEAD~`), fix imports with `dart fix --apply` + `dart analyze --fatal-infos`, add minimal `README.md` (purpose, install, usage snippet using real `lib/` export) and `example/<pkg>_example.dart` (runnable `Engine` with `test`/`serve` showing `ctx.json`/`ctx.cache` etc.), then `dart test`.
- Reuse existing helpers: copy `test_engine.dart`/`test_helpers.dart`/`support/property_generators.dart` from `packages/routed/test` or `server_*` where missing (as done for `server_storage` -> `routed_storage`).
- Keep `server_*` as source of truth; `routed_*` tests import `server_testing`/`routed_testing` not `routed/src`.

## Recommended Approach
Iterate package-by-package, one `gh stack` branch per package (atomic `git add -p`), verifying each before next: README → example → tests (import fix) → `dart analyze` + `dart test`. Start with `routed_cache` as pilot (smallest, already passing), then `routed_sessions` etc. Use `git show` to recover original tests; do not invent new coverage.

## Work Plan
1. **routed_cache** — Expand `README.md` (was 1 line), add `example/cache_example.dart` (Engine + DataCacheManager array store + `ctx.cache`/`getCache`), recover `provider/cache_provider_test.dart`, `engine/middleware_cache_test.dart`, `events/cache_event_test.dart` from history, fix imports, `dart test`.
2. **routed_sessions** — README+example (cookie store), recover `session` tests from `a5d240d1` (`server_sessions` move), wire `test_engine` helpers.
3. **routed_storage** — README+example (MemoryFileSystem + StorageManager), fix `static_files_test.dart` file_handler import (point to `server_storage` or `routed_io` future location; for now skip static tests or move to `server_storage`), add storage provider tests.
4. **routed_auth** — README already ok, add example run, ensure `test/auth/*` from `a5d240d1` present and imports `server_auth`.
5. **routed_http** — README+example (binding/json/multipart), ensure `binding_test.dart`, `sse_test.dart`, `negotiation_test.dart` present.
6. **routed_views** — README+example (view render), recover view tests.
7. **routed_validation** — README+example, recover validation tests.
8. **routed_rate_limit** — README (`server_rate_limit` adapter), example (RateLimitService + policy), tests from `server_rate_limit` (property tests) copied and adapted to `routed_rate_limit`.
9. **routed_analyzer / routed_cli / routed_openapi / routed_openapi_builder / routed_io / routed_config / routed** — each: README+example+existing tests (cli already has, openapi has, analyzer minimal).

## Validation Plan
- Per package: `dart analyze --fatal-infos packages/<pkg>/lib` → `No issues found!`
- Per package: `dart test packages/<pkg>` → `All tests passed!` (or `No tests ran` only where package intentionally has no runtime tests, e.g. `routed` re-export, `routed_config` facade)
- Spot-check example: `dart run packages/<pkg>/example/<example>.dart` exits 0 (no serve)
- Global: `git status --porcelain=v1` shows staged `README.md`, `example/`, `test/` per package, no collateral `yarn.lock`/`pubspec.lock` edits

## Risks / Rollback
- Risk: `file_handler`/`static` tests still reference deleted `routed/src/file_handler.dart` — will fail until `server_native`/`routed_io` owns it. Mitigation: skip/move those tests to `server_storage` where they already exist and pass, keep `routed_storage` lib tests only.
- Risk: import cycles if tests import `routed` + `server_*` with old `routed/src/*` paths — fix with `dart fix --apply` per package.
- Rollback: `git restore --staged` + `git restore` per package branch; `gh stack` keeps each package isolated.

## Open Questions
- None — pre-move tests located at `a5d240d1` and `server_*/test`; file_handler final home to be confirmed as `server_native` vs `routed_io` but not blocking per-package README/example pass.

