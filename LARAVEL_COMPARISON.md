# Laravel Feature Comparison

Snapshot of major capabilities provided by Laravel (across its core framework and first-party packages) that Routed does not yet match. Useful for setting expectations when teams evaluate Routed as an alternative.

## Application Structure & Controllers

- **Controllers & Routing Helpers** – Laravel ships controller base classes, middleware shortcuts, route resource helpers, and request validation decorators. Routed exposes low-level routers/handlers; controller scaffolding and resource routing remain manual.
- **Route Model Binding** – Laravel automatically resolves route parameters to Eloquent models, handling 404s when missing. Routed requires explicit lookups or custom middleware for this pattern.

## ORM & Database Layer

- **Eloquent ORM** – Laravel’s Active Record ORM provides relationships, attribute casting, observers, factories, and scopes. Routed intentionally stays database-agnostic; no built-in ORM exists.
- **Migrations & Schema Builder** – Laravel CLI (`php artisan make:migration`) scaffolds and runs schema migrations. Routed has no first-party migration tooling today.
- **Seeders & Factories** – Laravel populates databases through seed classes and model factories. Routed leaves seeding strategies to the application.

## Templates & Front-End

- **Blade Template Engine** – Laravel ships Blade syntax, layouts, components, and asset directives. Routed offers Liquid via packages but lacks Blade-equivalent helpers and asset directives.
- **Asset Pipeline (Vite/Laravel Mix)** – Laravel integrates Vite for asset bundling with versioned URLs. Routed’s static middleware serves files but has no bundler integration.

## Auth & Security

- **Authentication Guards** – Laravel provides session and token guards, password reset flows, email verification, and built-in login scaffolding. Routed includes session auth and gates but no turnkey UI or password management.
- **Gates & Policies** – Laravel ties authorization policies to models and actions with CLI tooling. Routed’s Haigate offers an authorization layer but the policy ecosystem is smaller and lacks generators.
- **CSRF & Security Middleware Defaults** – Laravel enables CSRF protection, secure cookies, HSTS, trusted proxies, and throttling out of the box. Routed exposes middleware primitives without an opinionated default stack.

## Background Work & Events

- **Queues & Jobs** – Laravel queues support multiple backends, delayed jobs, failed-job dashboards, and job batching. Routed does not ship a queue abstraction or workers.
- **Event Broadcasting** – Laravel broadcasts events over WebSockets/Pusher with channel auth. Routed would require custom implementations for real-time broadcasting.
- **Scheduler (Cron)** – Laravel’s task scheduler (`php artisan schedule:run`) orchestrates cron-like jobs. Routed currently has no scheduler helper.
- **Notifications & Mail** – Laravel’s notification channel system (mail, Slack, SMS) and mailable classes have no Routed equivalent.

## Storage & File Handling

- **Filesystem Abstraction** – Laravel’s Storage facade provides unified APIs over local/S3/etc. Routed offers storage drivers for uploads but lacks a cohesive abstraction and helpers.
- **Image & Media Helpers** – Laravel integrates with first-party packages for image resizing, responsive media, and URL signing; Routed leaves this to third-party packages.

## CLI & Tooling

- **Artisan CLI** – Laravel’s CLI scaffolds controllers/models/migrations, runs tests, seeds databases, manages queues, and provides a REPL. Routed CLI currently focuses on scaffolding starter apps, running the dev server, and inspecting manifests; no generators or REPL exist yet.
- **Environment Management** – Laravel’s CLI includes config cache, route cache, event/listener discovery, and queue management commands. Routed provides config caching/inspection but no caching for compiled routes/views or queue commands.

## Testing & Dev Experience

- **Test Harness** – Laravel’s test case bootstraps databases (migrate/seed), handles HTTP assertions, fakes mail/queue/events, and snapshots notifications. Routed depends on Dart’s `test` runner with lighter-weight helpers (`routed_testing`).
- **Telescope & Debugbar** – Laravel ships observability dashboards tracking requests, jobs, and queries. Routed offers logging hooks but no built-in dev dashboards.

## Package Ecosystem

- **First-Party Packages** – Cashier (billing), Jetstream/Breeze/Fortify (auth scaffolding), Scout (search), Horizon (queue dashboard), Sanctum/Passport (API tokens), Socialite (OAuth). Comparable Routed packages are currently minimal or community-driven.
- **Community Generators** – Laravel’s ecosystem includes a wide range of code generators and admin panels. Routed’s ecosystem is nascent with fewer drop-in packages.

## Internationalization

- **Localization & Timezones** – Laravel provides translation files, JSON language lines, pluralization, timezone helpers, and URL localization middleware. Routed has no built-in i18n localization tooling.

## REST & API Layer

- **API Resources & Transformers** – Laravel wraps responses in `JsonResource` for serialization, includes pagination helpers, and integrates with policies. Routed returns plain JSON unless developers build serialization layers themselves.
- **Rate Limiting & Throttling** – Laravel enforces per-route or per-user rate limits declaratively. Routed has low-level middleware support but not the expressive DSL.

## Deployment & Ops

- **Forge/Vapor Integration** – Laravel’s tooling ties into managed deployment platforms for provisioning, scaling, and serverless. Routed has no official managed offering yet.
- **Config/Route/View Caching** – Laravel optimizes production boot by compiling configs/routes/views; Routed loads YAML configs at runtime without compiled caches.

---

Routed focuses on the HTTP engine, middleware, service providers, and modular packages. Matching Laravel’s “battery-included” developer experience would require layered solutions for auth/scaffolding, queues, scheduling, storage, templating, CLI generators, testing harnesses, and the broader package ecosystem.
