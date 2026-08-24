# Website quality checklist

Use this checklist while building and before handing off a Routed/Liquify
website.

## Visual system

- [ ] The page has a clear visual point of view rather than framework-default
      styling.
- [ ] Typography has a deliberate scale, readable measure, and line height.
- [ ] Colors define both surface/text states and maintain contrast in light and
      dark themes.
- [ ] Spacing, radii, borders, shadows, and focus rings are consistent.
- [ ] The shell has an intentional desktop, tablet, and narrow-mobile layout.
- [ ] The important action is obvious without making every element a button.
- [ ] Empty, error, success, and loading states have the same design language.

## HTML and interaction

- [ ] There is one meaningful `h1`, followed by a logical heading hierarchy.
- [ ] Navigation, main content, forms, status messages, and footers use
      semantic landmarks.
- [ ] Every input has a visible label, a useful autocomplete value, and a
      server-side validation message.
- [ ] Links navigate; buttons submit or perform actions; do not swap their
      meanings for visual reasons.
- [ ] Keyboard focus is visible and never trapped by decorative interactions.
- [ ] Motion respects `prefers-reduced-motion` and never carries essential
      information alone.
- [ ] The first useful experience works without JavaScript.

## Routed and Liquid correctness

- [ ] Provider composition is typed and lives in `lib/config.dart`.
- [ ] Route handlers construct small view models instead of passing services or
      persistence objects into templates.
- [ ] File-backed pages use the configured view root; embedded pages use the
      same root for layouts and partials.
- [ ] All user-controlled Liquid output is escaped, including attributes and
      URLs.
- [ ] State-changing forms include the app's CSRF mechanism and reject unsafe
      origins or redirects.
- [ ] Authentication and authorization happen before rendering protected data.
- [ ] Errors returned to browsers are generic; detailed diagnostics stay in
      server logs.
- [ ] Static assets have stable URLs, correct content types, and an intentional
      cache policy.

## Validation

- [ ] Route tests assert body, status, headers, redirects, and cookies.
- [ ] Layout, block, render/include, escaping, and missing-template behavior
      have focused coverage.
- [ ] The app passes `dart format`, `dart analyze --fatal-infos`, and `dart test`.
- [ ] The CLI dev server starts from a clean checkout and serves the same
      engine factory used by deployment.
- [ ] A real browser check covers narrow and wide viewports, navigation, forms,
      auth transitions, contrast, and error states.
- [ ] The deployed origin is checked independently when deployment is in scope;
      local success is not deployment proof.
