# Static Mounts

A new [Routed](https://routed.dev) application.

## Getting started

```bash
dart pub get
dart run routed_cli dev
```

The default route responds with a friendly JSON payload. Edit
`lib/app.dart` to add additional routes, middleware, and providers. Static
files are served from `public/css` at `/css/*` and from `public` at
`/assets/*` using the direct engine helpers supported by the current package
bundle.
