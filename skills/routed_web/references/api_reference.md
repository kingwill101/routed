# Routed + Liquify view API

Use only public imports in application code:

```dart
import 'package:routed/routed.dart';
import 'package:routed_views/routed_views.dart';
```

For a slim composition, import `routed_core` and `routed_views` directly. The
current public view package exposes `RoutedViewConfig`,
`ViewServiceProvider`, `ViewEngine`, `LiquidViewEngine`, `LiquidRoot`,
`ViewEngineManager`, `EngineContext.template`, `EngineContext.view`,
`Engine.useViewEngine`, and `registerRoutedViewsProviders`.

## Filesystem-backed Dart IO composition

`RoutedViewConfig` owns typed startup configuration:

```dart
final engine = await Engine.create(
  providers: <ServiceProvider>[
    ...Engine.defaultProviders,
    ViewServiceProvider(
      RoutedViewConfig(
        directory: 'templates',
        engine: 'liquid',
        cache: true,
      ),
    ),
  ],
);

engine.get('/about', (ctx) {
  return ctx.template(
    templateName: 'pages/about.liquid',
    data: <String, dynamic>{
      'site_name': 'Example',
      'current_path': '/about',
    },
  );
});
```

`ctx.template` resolves a file through the configured view path and writes an
HTML response. It is the explicit choice for file-backed pages. `ctx.view` is
the view-engine render helper and may be appropriate for engines whose
`render` method accepts the template content/name directly; verify its loading
semantics when changing engines or roots.

For static files, compose `routed_storage`'s typed storage/static providers
and use `StaticConfig`/`StaticMountConfig`; keep assets separate from template
data. A typical public mount is `/assets` backed by a `public` directory or a
named storage disk.

## Engine and provider registration

Use one composition strategy per app:

1. Batteries-included: call `registerRoutedProviders()` once before engine
   creation, then supply typed application options/providers as required.
2. Explicit: pass `...Engine.defaultProviders` plus
   `ViewServiceProvider(...)` and any storage/static provider to
   `Engine.create(...)`.

Do not register providers after engine creation. Do not add a second registry
or configuration file to compensate for a missing provider.

## Shared layouts and blocks

Liquify supports layout inheritance and named blocks:

```liquid
{% layout "layouts/base.liquid" %}
{% block title %}About · {{ site_name | escape }}{% endblock %}
{% block content %}<h1>{{ heading | escape }}</h1>{% endblock %}
```

The layout and partials must be resolvable by the same Liquify root. Use
`{% render 'shared/card.liquid', item: item %}` for a partial with an explicit
scope. Use `| escape` on every untrusted value, especially values inserted in
attributes, URLs, titles, and inline JSON. Keep conditional/loop presentation
logic in templates but compute authorization, formatting, and data joins in
Dart.

## Filesystem-free hosts

Cloudflare Workers and other Fetch hosts do not provide the normal Dart IO
filesystem. Use `LiquidViewEngine` with a `LiquidRoot` backed by a memory or
bundle-backed `file.FileSystem`, or implement a small public `ViewEngine`
adapter around an embedded template map. Resolve the template name and all
layout/partial dependencies through that same root.

The host entrypoint should do only host work:

```dart
Future<Engine> createWorkerEngine(CloudflareEnvironment env) async {
  final app = await createEngine(
    viewEngine: embeddedLiquidEngine,
    // typed durable bindings and app providers
  );
  return app;
}
```

Keep `createEngine`, route registration, and view models host-neutral. Test the
embedded engine directly, because a filesystem-backed local test will not
catch a missing bundled partial or an unsupported host API.
