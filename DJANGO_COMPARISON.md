# Django Feature Comparison

Snapshot of higher-level capabilities Django bundles (outside its ORM/database layer) that Routed does not yet cover. Helpful for roadmap discussions.

## Admin & Auth

- **Admin site** – Django auto-generates CRUD screens from models (`django.contrib.admin`). Routed has no equivalent management UI.
- **Full auth stack** – Django ships a user model, password hashing, login/logout/password reset views, permissions, and groups. Routed currently offers session auth, guards, and Haigate; user management workflows are left to applications.

## Forms & UX Helpers

- **Form objects** – Django forms bind, validate, and render HTML (widgets, error messages) with CSRF baked in. Routed exposes low-level bind/validate primitives but no form objects or templating integration.
- **Message framework** – Django’s flash/message API ties into templates. Routed has session-based flash helpers without a first-class presentation layer.

## Internationalization

- **i18n & l10n** – Django bundles translation catalogs, `gettext` tooling, locale middleware, timezone utilities, and template tags. Routed lacks first-party translation/localisation support.

## Views & Shortcuts

- **Generic/Class-Based Views** – Django provides reusable view classes (ListView, DetailView, form mixins). Routed’s `class_view` package is early work and not yet comparable.
- **View shortcuts** – Helpers like `render`, `redirect`, `get_object_or_404`. Routed requires manual wiring for these patterns.

## Security Defaults

- **Security middleware** – Django enables clickjacking protection, secure cookies, HSTS, `ALLOWED_HOSTS`, XSS filter headers, and secure proxy handling by default. Routed exposes building blocks (CSRF middleware, IP filters) but doesn’t ship an opinionated security baseline yet.

## Static & Media Pipeline

- **Staticfiles app** – Django manages asset discovery, hashing, `collectstatic`, and template tags. Routed offers basic static serving/storage drivers without an asset pipeline.
- **Media storage abstraction** – Django integrates uploads with storage backends and URL helpers. Routed leaves media management to applications.

## CLI & Scaffolding

- **django-admin/manage.py** – Project/app scaffolding, migrations, dev server, shell, test runner, fixture loading. Routed’s CLI currently focuses on provider/config inspection and lacks scaffolds or app extension tooling.

## Signals & Events

- **Signals** – Django’s signals (e.g., `pre_save`, `post_request`) enable cross-cutting coordination. Routed now ships a request lifecycle signal hub (see `SignalHub` and request hooks), closing the gap for HTTP events. Broader ecosystem signals (model saves, mail events, etc.) are still application-specific.

## Testing Harness

- **Integrated test runner** – Django’s runner handles DB setup/teardown, fixtures, per-test client, management commands. Routed relies on Dart’s test runner; `routed_testing`/`server_testing` add helpers but remain lightweight.

## REST/Serialization Ecosystem

- **Django REST Framework** – Widely adopted extension for serializers, viewsets, routers. Routed ships only core HTTP primitives; REST scaffolding is up to consumers.

---

Routed excels as a modular HTTP engine with middleware, providers, session auth, and driver registries. Matching Django’s “batteries-included” experience would require layering higher-level tooling—admin UX, opinionated auth/forms/i18n, stronger security defaults, expanded CLI, and richer testing/REST ecosystems—on top of the current primitives.
