---
name: routed-web
description: Build polished, accessible, server-rendered websites with Routed and Liquify. Use when creating or improving a Routed website, choosing a view architecture, designing shared Liquid layouts and blocks, wiring typed view models and forms, serving locally, deploying through routed_cli, or validating a filesystem-backed or embedded view app.
---

# Routed web

Build the website as a real product surface: establish a visual system, keep
the application composition typed, render semantic HTML on the server, and
make the same route behavior testable on the target host. Use Routed for HTTP
and lifecycle composition, `routed_views` for view integration, and Liquify
for `.liquid` templates.

Read [api_reference.md](references/api_reference.md) when wiring providers,
layouts, embedded templates, or host-specific serving. Read
[quality-checklist.md](references/quality-checklist.md) before calling a page
finished.

## Choose the architecture first

- Use `package:routed/routed.dart` for a normal application that wants the
  official provider catalogue.
- Use `routed_core` plus explicit providers for a slim application or a
  reusable package. Do not make feature packages depend on the `routed`
  facade.
- Use `routed_views` with `ViewServiceProvider` and `RoutedViewConfig` for
  filesystem-backed templates on Dart IO.
- Use a custom `ViewEngine` with a bundled or in-memory Liquify root when the
  host has no filesystem, such as a Fetch/Workers runtime. Keep that adapter
  at the host or example boundary; do not make the route layer depend on JS
  interop.
- Keep `lib/config.dart` as the typed provider composition point, `lib/app.dart`
  as the portable engine and route surface, and `bin/` or host entrypoints as
  thin serving adapters. Do not introduce YAML, dotted-key configuration, or
  a global god-client for website concerns.

## Build workflow

### 1. Start from the Routed shape

For a new app, prefer the generated project shape:

```bash
dart run routed_cli:routed create
```

Keep the generated `config()`/`AppConfig` pattern and adapt it to the site.
Install `routed_cli` as a development dependency. Add only the providers the
site needs, with their typed constructors, and pass application dependencies
into an engine factory rather than reading environment variables in views.

For an existing app, inspect its public package barrels and current CLI
scaffold before adding a provider. Never document or import `lib/src/...`.

### 2. Define the visual system before pages

Choose a clear point of view for the site before writing repeated markup:

- define a restrained color system with explicit dark and light surface/text
  pairs;
- choose one display treatment and one readable body treatment, then set a
  deliberate type scale and line height;
- establish spacing, radii, borders, focus rings, content width, and responsive
  breakpoints as CSS variables or shared classes;
- give the shell a recognizable navigation, footer, active state, and mobile
  behavior;
- design loading, empty, validation-error, success, unauthenticated, and
  server-error states—not just the ideal screenshot;
- prefer semantic HTML, real buttons/links, visible focus, keyboard order,
  reduced-motion behavior, and sufficient contrast.

Do not generate a generic card grid with arbitrary gradients. Let the content,
hierarchy, and interaction model determine the composition. Use CSS and small
progressive-enhancement scripts for behavior; keep the first render useful
without JavaScript.

### 3. Compose typed routes and view models

Keep route handlers thin. Load data, authorize the request, construct a small
serializable view model, and render it. Do not pass a database object, secret,
request, or service locator into a template.

```dart
engine.get('/projects/{slug}', (ctx) async {
  final slug = ctx.param('slug');
  final project = await projects.findBySlug(slug);
  if (project == null) {
    return ctx.string('Not found', statusCode: HttpStatus.notFound);
  }

  return ctx.template(
    templateName: 'pages/project.liquid',
    data: <String, dynamic>{
      'title': project.title,
      'summary': project.summary,
      'features': project.features
          .map((feature) => <String, dynamic>{
                'name': feature.name,
                'description': feature.description,
              })
          .toList(growable: false),
    },
  );
});
```

Use `{slug}`/`ctx.param('slug')` for path parameters, validate and normalize
user input in Dart, and distinguish `404`, `403`, validation `422`, and
unexpected `500` responses. Escape user-controlled values in Liquid with the
`escape` filter, including attribute values and URLs.

### 4. Use shared Liquify layouts and blocks

Put the document shell in `templates/layouts/base.liquid`. Pages should select
the layout and override named blocks; components should be small and reusable.
Use Liquify's `layout`, `block`, `render`, `include`, `if`, `for`, `assign`, and
filters deliberately. Keep business decisions and data shaping in Dart.

```liquid
{%- comment -%} templates/layouts/base.liquid {%- endcomment -%}
<!doctype html>
<html lang="{{ html_lang | default: 'en' | escape }}">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{% block title %}{{ site_name | escape }}{% endblock %}</title>
    <link rel="stylesheet" href="/assets/site.css">
  </head>
  <body>
    {% render 'shared/nav.liquid', site_name: site_name, current_path: current_path %}
    <main id="main-content">
      {% block content %}{% endblock %}
    </main>
    {% block footer %}{% render 'shared/footer.liquid' %}{% endblock %}
  </body>
</html>
```

```liquid
{%- comment -%} templates/pages/project.liquid {%- endcomment -%}
{% layout "layouts/base.liquid" %}
{% block title %}{{ title | escape }} · {{ site_name | escape }}{% endblock %}
{% block content %}
  <article class="prose project-page">
    <p class="eyebrow">Project</p>
    <h1>{{ title | escape }}</h1>
    <p class="lede">{{ summary | escape }}</p>
    {% if features.size > 0 %}
      <ul>
        {% for feature in features %}
          <li>
            <h2>{{ feature.name | escape }}</h2>
            <p>{{ feature.description | escape }}</p>
          </li>
        {% endfor %}
      </ul>
    {% endif %}
  </article>
{% endblock %}
```

Prefer `{% render %}` for isolated partial data and `layout`/`block` for page
shell inheritance. Test layout inheritance and partial resolution explicitly;
one missing block or root path can otherwise produce a blank page only at
runtime.

### 5. Serve and deploy through the CLI

Use the Routed CLI as the recommended path so development, scaffolding, and
deployment exercise the same project contract:

```bash
dart run routed_cli:routed dev \
  --entry bin/server.dart \
  --host 127.0.0.1 \
  --port 8080
```

For a supported deployment target, use the corresponding typed deploy command
and keep secrets in the host's secret store. For Cloudflare, the application
factory should accept typed bindings from the Worker entrypoint and the
deployment should be driven by `routed_cli`; do not bake a personal hostname,
database ID, or token into the repository.

Keep a manual host command documented as a fallback when an operator needs
direct control, but make it equivalent to the CLI path: compile the correct
host entrypoint, configure the same typed providers, and run the same engine
factory. Never create a second route or template implementation for deployment.

## Test the site as a product

Add a focused route test with `routed_testing`/`server_testing` that exercises
the actual provider graph and asserts status, headers, redirects, and visible
HTML—not only that a handler returned a string.

At minimum cover:

- anonymous, authenticated, forbidden, not-found, and method-not-allowed
  behavior;
- path parameters, query/form validation, CSRF for state-changing forms, and
  safe redirect behavior;
- layout inheritance, partials, escaping of quotes/HTML/URLs, and missing data;
- responsive-critical landmarks, page title, heading hierarchy, labels, focus
  targets, and no-JavaScript form submission;
- static asset content types, cache policy, and missing assets;
- the same route factory on Dart IO and the intended Fetch/embedded host when
  the site targets both;
- production-like error handling that logs details server-side without
  returning secrets, paths, stack traces, or credentials to the browser.

Run the focused checks before handing off:

```bash
dart format --output=none --set-exit-if-changed lib bin test
dart analyze --fatal-infos .
dart test
```

Then run the CLI dev server and manually inspect the key flows at a narrow
viewport and a wide viewport. A passing analyzer or unit test is not visual
proof: verify contrast, overflow, navigation, form feedback, and error states
in a real browser when the change affects presentation.

## Failure modes to avoid

- Do not use internal imports from `routed_views` or Liquify in application
  code when a public barrel exposes the API.
- Do not put view logic, authorization, database calls, or secrets in Liquid.
- Do not render unescaped user data or mark arbitrary input as trusted HTML.
- Do not assume `ctx.view` and `ctx.template` have identical loading semantics;
  use `ctx.template(templateName: ...)` for file-backed templates and verify
  custom/embedded engines on the target host.
- Do not rely on a local filesystem in a Fetch runtime. Bundle templates or
  provide an explicit in-memory `ViewEngine` root.
- Do not copy framework cookies manually in feature handlers when a framework
  integration hook or session plugin owns the response lifecycle.
- Do not claim deployment success from a local build; check the deployed
  origin, assets, redirects, cookies, and error responses.
