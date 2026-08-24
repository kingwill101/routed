import 'package:liquify/liquify.dart' as liquid;
import 'package:routed_core/routed_core.dart';
import 'package:routed_views/routed_views.dart';

/// Templates bundled into the Worker instead of loaded from a filesystem.
///
/// Cloudflare Workers do not provide the normal Dart IO filesystem, so the
/// example adapts Liquify's in-memory root to Routed's public view-engine
/// contract. The same view route can therefore run on D1, Dart IO, and the
/// in-memory test server.
const _cloudflareAuthStyles = r'''
    :root {
      color-scheme: dark;
      --ink: #edf4ff;
      --muted: #9eacc1;
      --faint: #65748a;
      --line: rgba(163, 188, 221, .16);
      --panel: rgba(17, 27, 43, .86);
      --panel-strong: #111d2e;
      --accent: #7dd3fc;
      --accent-strong: #38bdf8;
      --success: #86efac;
      --danger: #fda4af;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      background:
        radial-gradient(circle at 15% 0%, rgba(56, 189, 248, .15), transparent 32rem),
        radial-gradient(circle at 90% 18%, rgba(129, 140, 248, .11), transparent 28rem),
        #08111f;
      color: var(--ink);
      line-height: 1.55;
      margin: 0;
      min-height: 100vh;
    }
    body::before {
      background-image: linear-gradient(rgba(125, 211, 252, .035) 1px, transparent 1px), linear-gradient(90deg, rgba(125, 211, 252, .035) 1px, transparent 1px);
      background-size: 34px 34px;
      content: "";
      inset: 0;
      mask-image: linear-gradient(to bottom, black, transparent 70%);
      pointer-events: none;
      position: fixed;
    }
    a { color: var(--accent); text-decoration: none; }
    a:hover { color: #bae6fd; }
    button, input { font: inherit; }
    button, .button {
      align-items: center;
      border: 1px solid rgba(125, 211, 252, .42);
      border-radius: .7rem;
      cursor: pointer;
      display: inline-flex;
      font-weight: 700;
      gap: .5rem;
      justify-content: center;
      padding: .75rem 1rem;
      transition: background .18s ease, border-color .18s ease, transform .18s ease;
    }
    button:hover, .button:hover { transform: translateY(-1px); }
    .button.primary, button.primary { background: var(--accent-strong); color: #04111c; }
    .button.primary:hover, button.primary:hover { background: #7dd3fc; }
    .button.ghost, button.ghost { background: rgba(125, 211, 252, .06); color: var(--ink); }
    .button.ghost:hover, button.ghost:hover { background: rgba(125, 211, 252, .14); }
    .shell { margin: 0 auto; max-width: 72rem; padding: 1.25rem 1.25rem 5rem; position: relative; }
    nav { align-items: center; display: flex; gap: 1.1rem; justify-content: space-between; padding: .4rem 0 4rem; }
    .brand { align-items: center; color: var(--ink); display: inline-flex; font-family: "SFMono-Regular", Consolas, monospace; font-size: .9rem; font-weight: 700; gap: .65rem; letter-spacing: .02em; }
    .brand-mark { background: var(--accent); border-radius: .25rem; box-shadow: 0 0 24px rgba(56, 189, 248, .65); height: .7rem; width: .7rem; }
    .nav-links { align-items: center; display: flex; flex-wrap: wrap; gap: 1rem; }
    .nav-links a, .nav-links button { background: transparent; border: 0; color: var(--muted); font-size: .88rem; padding: .25rem 0; }
    .nav-links a:hover, .nav-links button:hover { color: var(--ink); transform: none; }
    .eyebrow { color: var(--accent); font-family: "SFMono-Regular", Consolas, monospace; font-size: .73rem; letter-spacing: .16em; text-transform: uppercase; }
    h1, h2, h3 { letter-spacing: -.04em; line-height: 1.08; margin: 0; }
    h1 { font-size: clamp(2.6rem, 8vw, 6.5rem); max-width: 12ch; }
    h2 { font-size: clamp(1.8rem, 4vw, 3rem); }
    p { color: var(--muted); max-width: 62ch; }
    .lede { font-size: 1.08rem; margin: 1.4rem 0 0; }
    .hero { display: grid; gap: 2.5rem; grid-template-columns: minmax(0, 1.2fr) minmax(16rem, .8fr); padding: 1rem 0 4.5rem; }
    .hero-copy { align-self: end; }
    .hero-actions { display: flex; flex-wrap: wrap; gap: .75rem; margin-top: 2rem; }
    .signal { align-self: end; background: linear-gradient(145deg, rgba(18, 39, 60, .95), rgba(11, 22, 37, .82)); border: 1px solid var(--line); border-radius: 1rem; box-shadow: 0 20px 70px rgba(0, 0, 0, .22); padding: 1.15rem; }
    .signal-top { align-items: center; display: flex; gap: .65rem; justify-content: space-between; }
    .signal-label, .mono { color: var(--faint); font-family: "SFMono-Regular", Consolas, monospace; font-size: .76rem; }
    .signal-value { color: var(--success); font-family: "SFMono-Regular", Consolas, monospace; font-size: .8rem; }
    .signal-line { border-top: 1px solid var(--line); margin: 1rem 0; }
    .signal code { color: #c4e9ff; display: block; font-family: "SFMono-Regular", Consolas, monospace; font-size: .82rem; line-height: 1.8; }
    .route-grid { display: grid; gap: .8rem; grid-template-columns: repeat(2, minmax(0, 1fr)); margin-top: 1.3rem; }
    .route-card, .panel { background: var(--panel); border: 1px solid var(--line); border-radius: .9rem; }
    .route-card { display: block; padding: 1rem; }
    .route-card:hover { background: rgba(27, 48, 70, .92); border-color: rgba(125, 211, 252, .38); }
    .route-card strong { color: var(--ink); display: block; font-size: .92rem; }
    .route-card code { color: var(--faint); font-family: "SFMono-Regular", Consolas, monospace; font-size: .75rem; }
    .section-label { color: var(--faint); font-family: "SFMono-Regular", Consolas, monospace; font-size: .72rem; letter-spacing: .12em; text-transform: uppercase; }
    .auth-layout { display: grid; gap: 4rem; grid-template-columns: minmax(0, .9fr) minmax(20rem, .8fr); margin: 2rem auto 0; max-width: 60rem; }
    .auth-copy { padding-top: 1.5rem; }
    .auth-copy h1 { font-size: clamp(2.5rem, 6vw, 4.5rem); }
    .auth-form { background: linear-gradient(145deg, rgba(22, 37, 57, .96), rgba(11, 20, 34, .96)); border: 1px solid var(--line); border-radius: 1rem; box-shadow: 0 30px 90px rgba(0, 0, 0, .28); padding: clamp(1.3rem, 4vw, 2.2rem); }
    .auth-form h2 { font-size: 1.6rem; }
    .field { display: grid; gap: .45rem; margin-top: 1.1rem; }
    label { color: #c9d7e9; font-size: .86rem; font-weight: 650; }
    input { background: rgba(3, 10, 19, .64); border: 1px solid rgba(163, 188, 221, .25); border-radius: .55rem; color: var(--ink); outline: none; padding: .8rem .85rem; width: 100%; }
    input:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(56, 189, 248, .14); }
    .form-help { color: var(--faint); font-size: .78rem; margin: .45rem 0 0; }
    .form-submit { margin-top: 1.5rem; width: 100%; }
    .alert { background: rgba(190, 24, 93, .13); border: 1px solid rgba(253, 164, 175, .35); border-radius: .55rem; color: var(--danger); font-size: .88rem; margin-top: 1rem; padding: .75rem .85rem; }
    .success { background: rgba(34, 197, 94, .12); border: 1px solid rgba(134, 239, 172, .3); border-radius: .55rem; color: var(--success); font-size: .88rem; margin: 1rem 0; padding: .75rem .85rem; }
    .social-divider { align-items: center; color: var(--faint); display: flex; font-family: "SFMono-Regular", Consolas, monospace; font-size: .7rem; gap: .7rem; letter-spacing: .1em; margin: 1.5rem 0 1rem; text-transform: uppercase; }
    .social-divider::before, .social-divider::after { background: var(--line); content: ""; flex: 1; height: 1px; }
    .social-actions { display: grid; gap: .65rem; }
    .social-button { align-items: center; background: rgba(125, 211, 252, .05); border: 1px solid var(--line); border-radius: .6rem; color: var(--ink); display: flex; font-size: .86rem; font-weight: 700; justify-content: center; min-height: 2.8rem; padding: .65rem .8rem; text-align: center; }
    .social-button:hover { background: rgba(125, 211, 252, .12); border-color: rgba(125, 211, 252, .38); color: var(--ink); }
    .telegram-widget { align-items: center; background: rgba(125, 211, 252, .05); border: 1px solid var(--line); border-radius: .6rem; display: flex; justify-content: center; min-height: 2.8rem; overflow: hidden; padding: .55rem .8rem; }
    .switch { font-size: .85rem; margin: 1.3rem 0 0; text-align: center; }
    .dashboard-header { align-items: end; display: flex; gap: 2rem; justify-content: space-between; padding: 1rem 0 2.5rem; }
    .dashboard-header h1 { font-size: clamp(2.5rem, 6vw, 4.8rem); }
    .dashboard-grid { display: grid; gap: 1rem; grid-template-columns: repeat(3, minmax(0, 1fr)); }
    .metric { padding: 1.15rem; }
    .metric .value { color: var(--ink); font-size: 1.15rem; font-weight: 700; margin-top: .55rem; overflow-wrap: anywhere; }
    .dashboard-panels { display: grid; gap: 1rem; grid-template-columns: minmax(0, 1.2fr) minmax(0, .8fr); margin-top: 1rem; }
    .panel { padding: 1.35rem; }
    .panel h2 { font-size: 1.35rem; }
    .panel p { font-size: .9rem; }
    .panel-links { display: grid; gap: .65rem; margin-top: 1rem; }
    .panel-links a { border-bottom: 1px solid var(--line); display: flex; justify-content: space-between; padding: .7rem 0; }
    .panel-links a:last-child { border-bottom: 0; }
    .session-list { display: grid; gap: .75rem; margin: 1rem 0 1.25rem; }
    .session-row { align-items: center; border-bottom: 1px solid var(--line); display: flex; gap: 1rem; justify-content: space-between; padding: .8rem 0; }
    .session-row:last-child { border-bottom: 0; }
    .session-row strong { color: var(--ink); display: block; }
    .session-current { border: 1px solid rgba(134, 239, 172, .35); border-radius: 999px; color: var(--success); font-family: "SFMono-Regular", Consolas, monospace; font-size: .7rem; padding: .25rem .5rem; text-transform: uppercase; }
    footer { color: var(--faint); font-family: "SFMono-Regular", Consolas, monospace; font-size: .75rem; margin-top: 4rem; }
    @media (max-width: 720px) {
      nav { align-items: flex-start; flex-direction: column; padding-bottom: 2.5rem; }
      .hero, .auth-layout, .dashboard-panels { grid-template-columns: 1fr; }
      .hero { padding-bottom: 3rem; }
      .route-grid, .dashboard-grid { grid-template-columns: 1fr; }
      .dashboard-header { align-items: flex-start; flex-direction: column; }
    }
''';

const _cloudflareAuthStyleBlock = '<style>$_cloudflareAuthStyles</style>';

const cloudflareAuthEmbeddedViews = <String, String>{
  'layouts/base.liquid':
      '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{% block title %}Routed Cloudflare Auth{% endblock %}</title>
  $_cloudflareAuthStyleBlock
</head>
<body>
  <div class="shell">
    <nav>
      {% include "partials/brand.liquid" %}
      <div class="nav-links">
        {% block navigation %}{% endblock %}
      </div>
    </nav>
    <main>
      {% block content %}{% endblock %}
    </main>
    <footer>
      {% block footer %}Routed routes, typed providers, and portable views.{% endblock %}
    </footer>
  </div>
</body>
</html>
''',
  'partials/brand.liquid':
      '''<a class="brand" href="/"><span class="brand-mark"></span>routed / edge-auth</a>''',
  'home.liquid': '''{% layout "layouts/base.liquid" %}
{% block title %}{{ title | escape }}{% endblock %}
{% block navigation %}
        {% if authenticated %}
          <a href="/dashboard">Dashboard</a>
          <form action="/logout" method="post">
            <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
            <button type="submit">Sign out</button>
          </form>
        {% else %}
          <a href="/login">Sign in</a>
          <a href="/signup">Create account</a>
        {% endif %}
{% endblock %}
{% block content %}
      <section class="hero">
        <div class="hero-copy">
          <div class="eyebrow">Routed + Cloudflare D1</div>
          <h1>{{ title | escape }}</h1>
          <p class="lede">{{ description | escape }}</p>
          <div class="hero-actions">
            {% if authenticated %}
              <a class="button primary" href="/dashboard">Open dashboard</a>
            {% else %}
              <a class="button primary" href="/signup">Start with an account</a>
              <a class="button ghost" href="/login">Sign in</a>
            {% endif %}
          </div>
        </div>
        <aside class="signal">
          <div class="signal-top"><span class="signal-label">DEPLOYMENT STATUS</span><span class="signal-value">● {{ status | escape }}</span></div>
          <div class="signal-line"></div>
          <code>runtime   cloudflare workers</code>
          <code>storage   d1 / auth database</code>
          <code>views     embedded liquify</code>
        </aside>
      </section>
      <section>
        <div class="section-label">Portable route surface</div>
        <div class="route-grid">
          {% for route in routes %}
            <a class="route-card" href="{{ route.path | escape }}"><strong>{{ route.label | escape }}</strong><code>{{ route.path | escape }}</code></a>
          {% endfor %}
        </div>
      </section>
{% endblock %}
{% block footer %}One application surface, with typed providers behind it.{% endblock %}
''',
  'auth.liquid': '''{% layout "layouts/base.liquid" %}
{% block title %}{{ title | escape }}{% endblock %}
{% block navigation %}<a href="/">Back home</a>{% endblock %}
{% block content %}
      <div class="auth-layout">
      <section class="auth-copy">
        <div class="eyebrow">{{ form_title | escape }}</div>
        <h1>{{ title | escape }}</h1>
        <p class="lede">{{ form_copy | escape }}</p>
        <p class="mono">Protected by signed session cookies, origin checks, and CSRF tokens.</p>
      </section>
      <section class="auth-form">
        <h2>{{ form_title | escape }}</h2>
        <p>{{ form_copy | escape }}</p>
        {% if password_changed %}<div class="success" role="status">Password changed. Sign in again to continue.</div>{% endif %}
        {% if error %}<div class="alert" role="alert">{{ error | escape }}</div>{% endif %}
        <form action="{{ form_action | escape }}" method="post">
          <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
          <div class="field">
            <label for="email">Email address</label>
            <input id="email" name="email" type="email" value="{{ email | escape }}" autocomplete="email" required autofocus>
          </div>
          <div class="field">
            <label for="password">Password</label>
            <input id="password" name="password" type="password" autocomplete="{{ password_autocomplete | escape }}" minlength="12" required>
            <div class="form-help">Use at least 12 characters.</div>
          </div>
          <button class="primary form-submit" type="submit">{{ submit_label | escape }}</button>
        </form>
        {% if has_social_providers %}
          <div class="social-divider">or continue with</div>
          <div class="social-actions">
            {% if github_enabled %}
              <a class="social-button" href="/auth/signin/github?callbackUrl=%2Fdashboard">Continue with GitHub</a>
            {% endif %}
            {% if dropbox_enabled %}
              <a class="social-button" href="/auth/signin/dropbox?callbackUrl=%2Fdashboard">Continue with Dropbox</a>
            {% endif %}
            {% if telegram_enabled %}
              <div class="telegram-widget">
                <script async src="https://telegram.org/js/telegram-widget.js?22" data-telegram-login="{{ telegram_bot_username | escape }}" data-size="large" data-auth-url="{{ telegram_redirect_uri | escape }}" data-request-access="write"></script>
              </div>
            {% endif %}
          </div>
        {% endif %}
        <p class="switch">{{ switch_copy | escape }} <a href="{{ switch_href | escape }}">{{ switch_label | escape }}</a></p>
      </section>
      </div>
{% endblock %}
{% block footer %}{% endblock %}
''',
  'dashboard.liquid': '''{% layout "layouts/base.liquid" %}
{% block title %}Dashboard · Routed Cloudflare Auth{% endblock %}
{% block navigation %}
        <a href="/">Home</a>
        <a href="/settings/profile">Profile</a>
        <a href="/settings/password">Password</a>
        <a href="/settings/api-keys">Service keys</a>
        <a href="/settings/sessions">Sessions</a>
        <form action="/logout" method="post">
          <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
          <button type="submit">Sign out</button>
        </form>
{% endblock %}
{% block content %}
      <section class="dashboard-header">
        <div>
          <div class="eyebrow">Authenticated workspace</div>
          <h1>Good to see you.</h1>
          <p class="lede">This page is protected by the same session middleware used by the JSON account endpoint.</p>
        </div>
        <a class="button ghost" href="/account">View account JSON</a>
      </section>
      <section class="dashboard-grid">
        <div class="panel metric"><div class="section-label">Signed in as</div><div class="value">{{ email | escape }}</div></div>
        <div class="panel metric"><div class="section-label">Display name</div><div class="value">{{ name | escape }}</div></div>
        <div class="panel metric"><div class="section-label">Session strategy</div><div class="value">{{ session_strategy | escape }}</div></div>
        <div class="panel metric"><div class="section-label">Expires</div><div class="value">{{ session_expires | escape }}</div></div>
      </section>
      <section class="dashboard-panels">
        <div class="panel">
          <div class="section-label">Identity record</div>
          <h2>Your account is live</h2>
          <p>The credential is stored in the configured AuthStore. On Cloudflare, that store is backed by D1 while session state stays in an encrypted cookie.</p>
          <div class="panel-links">
            <a href="/settings/profile"><span>Edit profile</span><span>↗</span></a>
            <a href="/settings/password"><span>Change password</span><span>↗</span></a>
            <a href="/settings/api-keys"><span>Manage service keys</span><span>↗</span></a>
            <a href="/settings/sessions"><span>Manage sessions</span><span>↗</span></a>
            <a href="/auth/session"><span>Inspect session payload</span><span>↗</span></a>
            <a href="/health"><span>Check deployment health</span><span>↗</span></a>
          </div>
        </div>
        <div class="panel">
          <div class="section-label">User ID</div>
          <h2 class="mono">{{ user_id | escape }}</h2>
          <p>Keep this identifier server-side when connecting the dashboard to application data.</p>
        </div>
      </section>
{% endblock %}
''',
  'profile.liquid': '''{% layout "layouts/base.liquid" %}
{% block title %}Profile · Routed Cloudflare Auth{% endblock %}
{% block navigation %}
        <a href="/dashboard">Dashboard</a>
        <a href="/settings/password">Password</a>
        <a href="/settings/api-keys">Service keys</a>
        <a href="/settings/sessions">Sessions</a>
        <form action="/logout" method="post">
          <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
          <button type="submit">Sign out</button>
        </form>
{% endblock %}
{% block content %}
      <div class="auth-layout">
        <section class="auth-copy">
          <div class="eyebrow">Account settings</div>
          <h1>Make it yours.</h1>
          <p class="lede">Update the profile stored in D1 and refresh the signed session projection in the same request.</p>
          <p class="mono">Your email remains the credential identifier in this demo.</p>
        </section>
        <section class="auth-form">
          <h2>Profile</h2>
          <p>{{ email | escape }}</p>
          {% if updated %}<div class="success" role="status">Profile saved.</div>{% endif %}
          {% if error %}<div class="alert" role="alert">{{ error | escape }}</div>{% endif %}
          <form action="/settings/profile" method="post">
            <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
            <div class="field">
              <label for="name">Display name</label>
              <input id="name" name="name" type="text" value="{{ name | escape }}" maxlength="80" autocomplete="name">
            </div>
            <div class="field">
              <label for="image">Profile image URL</label>
              <input id="image" name="image" type="url" value="{{ image | escape }}" maxlength="2048" placeholder="https://example.com/avatar.png" autocomplete="url">
              <div class="form-help">Use an HTTPS image URL or leave it blank to clear it.</div>
            </div>
            <button class="primary form-submit" type="submit">Save profile</button>
          </form>
        </section>
      </div>
      <section class="panel" style="margin: 1rem auto 0; max-width: 60rem;">
        <div class="section-label">Connected providers</div>
        <h2>Linked accounts</h2>
        {% if has_accounts %}
          <div class="session-list">
            {% for account in accounts %}
              <div class="session-row"><strong>{{ account.provider_id | escape }}</strong><span class="mono">{{ account.provider_account_id | escape }}</span></div>
            {% endfor %}
          </div>
        {% else %}
          <p>No external accounts are linked yet. Sign in with GitHub, Dropbox, or Telegram to exercise provider linking.</p>
        {% endif %}
      </section>
{% endblock %}
{% block footer %}{% endblock %}
''',
  'password.liquid': '''{% layout "layouts/base.liquid" %}
{% block title %}Password · Routed Cloudflare Auth{% endblock %}
{% block navigation %}
        <a href="/dashboard">Dashboard</a>
        <a href="/settings/profile">Profile</a>
        <a href="/settings/api-keys">Service keys</a>
        <a href="/settings/sessions">Sessions</a>
        <form action="/logout" method="post">
          <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
          <button type="submit">Sign out</button>
        </form>
{% endblock %}
{% block content %}
      <div class="auth-layout">
        <section class="auth-copy">
          <div class="eyebrow">Security settings</div>
          <h1>Change your password.</h1>
          <p class="lede">Reauthenticate before replacing the credential used by this account.</p>
          <p class="mono">Changing a password signs out every active session, including this browser.</p>
        </section>
        <section class="auth-form">
          <h2>Password</h2>
          <p>{{ email | escape }}</p>
          {% if error %}<div class="alert" role="alert">{{ error | escape }}</div>{% endif %}
          <form action="/settings/password" method="post">
            <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
            <div class="field">
              <label for="current-password">Current password</label>
              <input id="current-password" name="current_password" type="password" autocomplete="current-password" required>
            </div>
            <div class="field">
              <label for="new-password">New password</label>
              <input id="new-password" name="new_password" type="password" autocomplete="new-password" minlength="12" required>
              <div class="form-help">Use at least 12 characters.</div>
            </div>
            <div class="field">
              <label for="new-password-confirmation">Confirm new password</label>
              <input id="new-password-confirmation" name="new_password_confirmation" type="password" autocomplete="new-password" minlength="12" required>
            </div>
            <button class="primary form-submit" type="submit">Change password</button>
          </form>
        </section>
      </div>
{% endblock %}
{% block footer %}{% endblock %}
''',
  'api_keys.liquid': '''{% layout "layouts/base.liquid" %}
{% block title %}Service keys · Routed Cloudflare Auth{% endblock %}
{% block navigation %}
        <a href="/dashboard">Dashboard</a>
        <a href="/settings/profile">Profile</a>
        <a href="/settings/password">Password</a>
        <a href="/settings/sessions">Sessions</a>
        <form action="/logout" method="post">
          <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
          <button type="submit">Sign out</button>
        </form>
{% endblock %}
{% block content %}
      <section class="dashboard-header">
        <div>
          <div class="eyebrow">Developer access</div>
          <h1>Service keys.</h1>
          <p class="lede">Issue narrowly scoped credentials for scripts and services. The raw key is shown only once.</p>
        </div>
      </section>
      {% if issued_key %}
        <section class="panel success" role="status">
          <strong>Copy this key now.</strong>
          <p>The raw value for {{ issued_name | escape }} will not be shown again.</p>
          <code>{{ issued_key | escape }}</code>
        </section>
      {% endif %}
      {% if reauthenticated %}<div class="success" role="status">Fresh authentication verified. You can now change service credentials.</div>{% endif %}
      {% if error %}<div class="alert" role="alert">{{ error | escape }}</div>{% endif %}
      {% if reauthentication_required %}
        <section class="panel" style="margin-bottom: 1rem;">
          <div class="section-label">Security check</div>
          <h2>Reauthenticate to continue.</h2>
          <p>Your session is still active, but changing service credentials requires a recent password check.</p>
          <form action="/settings/reauthenticate" method="post">
            <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
            <div class="field">
              <label for="reauth-password">Current password</label>
              <input id="reauth-password" name="password" type="password" autocomplete="current-password" required autofocus>
            </div>
            <button class="primary form-submit" type="submit">Verify and continue</button>
          </form>
        </section>
      {% endif %}
      <section class="dashboard-panels">
        <div class="panel">
          <div class="section-label">Create a key</div>
          <h2>New service credential</h2>
          <form action="/settings/api-keys/create" method="post">
            <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
            <div class="field">
              <label for="key-name">Name</label>
              <input id="key-name" name="name" type="text" maxlength="80" placeholder="deploy bot" required>
            </div>
            <div class="field">
              <label for="key-scopes">Scopes</label>
              <input id="key-scopes" name="scopes" type="text" placeholder="profile:read, deploy:read">
              <div class="form-help">Comma-separated scope labels. Keep them as narrow as possible.</div>
            </div>
            <button class="primary form-submit" type="submit">Issue service key</button>
          </form>
        </div>
        <div class="panel">
          <div class="section-label">Protected service route</div>
          <h2><code>GET /service/account</code></h2>
          <p>Send <code>X-API-Key</code> with one of these keys to authenticate without a browser session.</p>
        </div>
      </section>
      <section class="panel" style="margin-top: 1rem;">
        <div class="section-label">Issued keys · {{ key_count }}</div>
        <div class="session-list">
          {% for key in keys %}
            <div class="session-row">
              <div>
                <strong>{{ key.name | escape }}</strong>
                <div class="mono">{{ key.keyPrefix | escape }} · {{ key.scopes | join: ", " | escape }}</div>
              </div>
              <div class="hero-actions" style="margin-top: 0;">
                {% if key.active %}
                  <form action="/settings/api-keys/rotate" method="post">
                    <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
                    <input type="hidden" name="id" value="{{ key.id | escape }}">
                    <input type="hidden" name="name" value="{{ key.name | escape }}">
                    <button class="button ghost" type="submit">Rotate</button>
                  </form>
                  <form action="/settings/api-keys/revoke" method="post">
                    <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
                    <input type="hidden" name="id" value="{{ key.id | escape }}">
                    <button class="button ghost" type="submit">Revoke</button>
                  </form>
                {% else %}
                  <span class="session-current">revoked</span>
                {% endif %}
              </div>
            </div>
          {% endfor %}
        </div>
      </section>
{% endblock %}
{% block footer %}{% endblock %}
''',
  'sessions.liquid': '''{% layout "layouts/base.liquid" %}
{% block title %}Sessions · Routed Cloudflare Auth{% endblock %}
{% block navigation %}
        <a href="/dashboard">Dashboard</a>
        <a href="/settings/profile">Profile</a>
        <a href="/settings/password">Password</a>
        <a href="/settings/api-keys">Service keys</a>
        <form action="/logout" method="post">
          <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
          <button type="submit">Sign out</button>
        </form>
{% endblock %}
{% block content %}
      <section class="dashboard-header">
        <div>
          <div class="eyebrow">Security settings</div>
          <h1>Your sessions.</h1>
          <p class="lede">Review active server sessions and revoke every other session while keeping this browser signed in.</p>
        </div>
      </section>
      {% if revoked_notice %}<div class="success" role="status">{{ revoked_notice | escape }}</div>{% endif %}
      {% if error %}<div class="alert" role="alert">{{ error | escape }}</div>{% endif %}
      <section class="panel">
        <div class="section-label">Active sessions · {{ session_count }}</div>
        <div class="session-list">
          {% for session in sessions %}
            <div class="session-row">
              <div>
                <strong>{% if session.isCurrent %}This browser{% else %}Other session{% endif %}</strong>
                <div class="mono">{{ session.authenticationMethod | escape }} · last used {{ session.lastUsedAt | escape }}</div>
              </div>
              {% if session.isCurrent %}<span class="session-current">current</span>{% endif %}
            </div>
          {% endfor %}
        </div>
        <form action="/settings/sessions/revoke-others" method="post">
          <input type="hidden" name="_csrf" value="{{ csrf_token | escape }}">
          <button class="button ghost" type="submit">Revoke other sessions</button>
        </form>
      </section>
{% endblock %}
{% block footer %}{% endblock %}
''',
};

/// A [ViewEngine] that resolves named templates from an embedded Liquify root.
final class EmbeddedLiquidViewEngine implements ViewEngine {
  EmbeddedLiquidViewEngine(Map<String, String> templates)
    : _templates = Map<String, String>.unmodifiable(templates),
      _root = liquid.MapRoot(templates);

  final Map<String, String> _templates;
  final liquid.Root _root;

  @override
  List<String> get extensions => const ['.liquid', '.html'];

  @override
  Future<String> render(String name, [Map<String, dynamic>? data]) async {
    final template = _templates[name];
    if (template == null) {
      throw TemplateNotFoundException(name);
    }
    final parsed = liquid.Template.parse(
      template,
      data: data ?? const <String, dynamic>{},
      root: _root,
    );
    return parsed.renderAsync();
  }

  @override
  Future<String> renderFile(String filePath, [Map<String, dynamic>? data]) =>
      render(filePath, data);
}

/// Registers the embedded view engine without introducing filesystem access.
final class EmbeddedViewsProvider extends ServiceProvider {
  EmbeddedViewsProvider({
    Map<String, String> templates = cloudflareAuthEmbeddedViews,
  }) : _engine = EmbeddedLiquidViewEngine(templates);

  final EmbeddedLiquidViewEngine _engine;

  @override
  void register(Container container) {
    final manager = ViewEngineManager()..register(_engine);
    container.instance<EmbeddedLiquidViewEngine>(_engine);
    container.instance<ViewEngineManager>(manager);
  }
}
