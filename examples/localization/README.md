# Localization Example

Demonstrates how to serve localized content with Routed's translation
provider, helper functions, and default locale resolvers.

## Getting started

```bash
cd examples/localization
dart pub get
dart run routed_cli dev
```

## Usage

Routes:

- `/` – default resolver chain (query → cookie → header) with translations
  pulled from `resources/lang/<locale>/messages.yaml` plus
  `resources/lang/json/<locale>.json`.
- `/preview` – highlights the custom resolver registered in `lib/app.dart`.
  Supply `?preview=true&preview_locale=es` to override the locale without
  touching cookies or headers.
- `/header` – illustrates the header resolver by echoing the incoming
  `Accept-Language` header alongside the localized payload.

The locale defaults to `en` but can be overridden with either:

- `?preview=true&preview_locale=es` – exercises the custom `preview` resolver
  registered in `lib/app.dart` and configured via `translation.resolver_options`.
- `?locale=es` – falls back to the built-in query resolver.

```bash
# English (default route)
curl 'http://127.0.0.1:8080/?name=Kai&notifications=3'

# Custom preview resolver
curl 'http://127.0.0.1:8080/preview?preview=true&preview_locale=es'

# Built-in query resolver
curl 'http://127.0.0.1:8080/?locale=es&name=Ana&notifications=1'

# Header resolver
curl -H 'Accept-Language: es' 'http://127.0.0.1:8080/header'
```

Edit `resources/lang/en/messages.yaml` (and sibling locale files) or add new
ones to expand the dictionary. See `lib/app.dart` for how `trans`,
`transChoice`, and `currentLocale` tie everything together.
