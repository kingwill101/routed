## Unreleased

- Completed public Dartdoc coverage and enabled the `public_member_api_docs`
  analyzer lint.
- Clarified typed provider configuration, view-engine lifecycle, request
  rendering, locale resolution, translation loading, and Liquid integration.

## 0.2.0

- **Breaking:** Replace localization resolver IDs, resolver option maps, and
  `LocaleResolverRegistry` with `List<LocaleResolver>` in
  `LocalizationConfig`; construct built-in and custom resolvers directly.
- Moved the current view, render, and translation helpers behind the standalone
  `routed_views` package.
- Updated localization and view providers and exposed the current template
  engine integration.
- Provider startup configuration is now documented and supplied through the
  typed `RoutedViewConfig` and `LocalizationConfig` constructors.

## 0.1.0

- Initial package scaffold for the routed modular package split.
