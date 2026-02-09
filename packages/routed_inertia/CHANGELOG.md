## 0.1.1

- Eliminated code duplication -- extracted shared helpers (`inertiaRequestUrl`,
  `inertiaDefaultHtml`, `consumeFlash`, `consumeErrors`,
  `consumeClearHistoryFlag`, `resolveInertiaConfig`, `resolveInertiaAssets`)
  into `inertia_utils.dart`. Header extraction and HTML escaping now delegate
  to `extractHttpHeaders()` / `escapeInertiaHtml()` from `inertia_dart`.
- Uses `InertiaRequest` and `InertiaResponse` from `inertia_dart` instead of
  manual header checks, ensuring correct Inertia protocol header propagation.
  `RoutedInertiaMiddleware` uses `InertiaHeaders.inertiaLocation` constant.
- `ctx.inertia()` gains an `includeAssets` parameter (default `true`) that
  resolves Vite assets via the new `resolveInertiaAssets()` helper and passes
  `inertia_styles` / `inertia_scripts` to the template data automatically.
  Note: the standalone `RoutedInertia.render()` API does not yet support
  `includeAssets`.
- Replaced private context key strings with a shared `InertiaKeys` class.
- Re-exports `InertiaViteAssets`, `InertiaViteAssetTags`, `PageData`,
  `SsrResponse`, and all core Inertia middlewares (`EncryptHistoryMiddleware`,
  `ErrorHandlingMiddleware`, `InertiaMiddleware`, `RedirectMiddleware`,
  `SharedDataMiddleware`, `VersionMiddleware`) from the package barrel.
- Added `InertiaEncryptHistoryMiddleware` for Routed-specific history
  encryption middleware integration.

## 0.1.0

- Initial release of Routed Inertia integration.
- Adds middleware, EngineContext helpers, and config-driven defaults.
- Supports SSR gateway wiring and asset manifest helpers.
- Includes provider registration and integration tests.
