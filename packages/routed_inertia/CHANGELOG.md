## 0.1.1

- Eliminated code duplication -- extracted shared helpers (`_extractHeaders`,
  `_escapeHtml`, `_defaultHtml`, `_requestUrl`, `_applyForwardedPrefix`,
  flash/error/history consumers, config resolution) into `inertia_utils.dart`.
- Uses `InertiaRequest` and `InertiaResponse` from `inertia_dart` instead of
  manual header checks, ensuring correct Inertia protocol header propagation.
- `inertiaRender()` gains an `includeAssets` parameter (default `true`) that
  resolves Vite assets and passes `inertia_styles` / `inertia_scripts` to the
  template data automatically.
- Replaced private context key strings with a shared `InertiaKeys` class.
- Re-exports `InertiaViteAssets`, `InertiaViteAssetTags`, `PageData`, and
  `SsrResponse` from the package barrel.

## 0.1.0

- Initial release of Routed Inertia integration.
- Adds middleware, EngineContext helpers, and config-driven defaults.
- Supports SSR gateway wiring and asset manifest helpers.
- Includes provider registration and integration tests.
