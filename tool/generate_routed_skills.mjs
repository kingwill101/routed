#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const packagesRoot = path.join(repoRoot, 'packages');
const skillsRoot = path.join(repoRoot, 'skills');
const catalogPath = path.join(repoRoot, 'docs', 'package-catalog.md');
const checkOnly = process.argv.includes('--check');

// Cross-cutting skills live beside the generated package skills but are not
// derived from a single package manifest. Keep them explicit so the catalog
// check can distinguish intentional skills from stale package directories.
const supplementalSkills = [
  {
    directory: 'routed_web',
    name: 'routed-web',
    summary: 'Build polished, server-rendered websites with Routed and Liquify.',
  },
];

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function walk(directory, predicate) {
  const results = [];
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    if (entry.name === 'example' || entry.name === 'examples' || entry.name === 'benchmarks') continue;
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      results.push(...walk(entryPath, predicate));
    } else if (predicate(entryPath, entry.name)) {
      results.push(entryPath);
    }
  }
  return results;
}

function scalar(manifest, key) {
  const match = manifest.match(new RegExp(`^${key}:\\s*(?:"([^"]*)"|'([^']*)'|(.+?))\\s*$`, 'm'));
  return match?.[1] ?? match?.[2] ?? match?.[3] ?? '';
}

function packageDependencies(manifest) {
  const dependencies = new Set();
  let section = '';
  for (const line of manifest.split('\n')) {
    const sectionMatch = line.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*$/);
    if (sectionMatch) {
      section = sectionMatch[1] === 'dependencies' ? 'dependencies' : '';
      continue;
    }
    if (!section || !/^\s{2}[A-Za-z0-9_]+:/.test(line)) continue;
    const name = line.match(/^\s{2}([A-Za-z0-9_]+):/)?.[1];
    if (name && /^(?:routed(?:_|$)|server_)/.test(name)) dependencies.add(name);
  }
  return [...dependencies].sort();
}

function catalogRoles() {
  if (!fs.existsSync(catalogPath)) return new Map();
  const roles = new Map();
  for (const line of read(catalogPath).split('\n')) {
    const match = line.match(/^\| \[`([^`]+)`\]\([^)]*\) \| `[^`]+` \| (.+) \|$/);
    if (match) roles.set(match[1], match[2].trim());
  }
  return roles;
}

function packageInfo(manifestPath, roles) {
  const packageRoot = path.dirname(manifestPath);
  const manifest = read(manifestPath);
  const name = scalar(manifest, 'name');
  if (!(name === 'routed' || name.startsWith('routed_'))) return null;

  const libDirectory = path.join(packageRoot, 'lib');
  const libFiles = fs.existsSync(libDirectory)
    ? fs.readdirSync(libDirectory, {withFileTypes: true})
        .filter((entry) => entry.isFile() && entry.name.endsWith('.dart'))
        .map((entry) => entry.name)
        .sort()
    : [];
  const testFiles = fs.existsSync(path.join(packageRoot, 'test'))
    ? walk(path.join(packageRoot, 'test'), (file, fileName) => fileName.endsWith('.dart'))
    : [];
  const exampleFiles = fs.existsSync(path.join(packageRoot, 'example'))
    ? walk(path.join(packageRoot, 'example'), () => true)
    : [];
  return {
    name,
    directory: path.relative(repoRoot, packageRoot),
    version: scalar(manifest, 'version'),
    description: scalar(manifest, 'description'),
    role: roles.get(name) ?? 'Routed subsystem; confirm ownership in the package README.',
    libFiles,
    dependencyNames: packageDependencies(manifest),
    testCount: testFiles.length,
    exampleCount: exampleFiles.length,
    hasReadme: fs.existsSync(path.join(packageRoot, 'README.md')),
  };
}

const subsystemData = {
  routed: {
    summary: 'The batteries-included application facade. It re-exports core and the official feature adapters, and exposes the one-time provider registration helper.',
    api: [
      '`registerRoutedProviders()` registers the official provider catalogue; call it once before `Engine.create()`.',
      '`Engine.create()` then boots the core plus registered feature providers.',
      'The facade exports routed_core, routed_auth, routed_cache, routed_sessions, routed_storage, routed_rate_limit, routed_views, routed_http, routed_logging, routed_observability, routed_openapi, routed_security, and routed_validation.',
      'Typed provider constructors own feature configuration; there is no YAML or dotted-key configuration surface.',
    ],
    compose: [
      'Use this package for normal applications that want the official provider set.',
      'For a slim app, use routed_core and add only the adapters needed; do not make adapters depend on this facade.',
      'When adding a provider to the official bundle, update the export, registration order, provider-count expectations, and a facade bootstrap test.',
    ],
    pitfalls: [
      'Do not register the catalogue after engine creation; late registration does not retroactively boot providers.',
      'Do not hide typed provider configuration behind a new global config format.',
      'Keep host transport separate: VM serving uses routed_io, while JavaScript hosts use routed_node.',
    ],
    tests: 'Exercise a minimal health route, provider registration before engine creation, and a second explicit-provider composition for any catalogue change.',
    quickStart: [
      "import 'package:routed/routed.dart';",
      '',
      'Future<void> main() async {',
      '  registerRoutedProviders();',
      '  final engine = await Engine.create();',
      "  engine.get('/health', (ctx) => ctx.json({'ok': true}));",
      '  await engine.serve(port: 8080);',
      '}',
    ],
  },
  routed_analyzer: {
    summary: 'The Dart analyzer plugin for route schema and validation metadata. It is development-time tooling, not an Engine provider.',
    api: [
      '`RoutedAnalyzerPlugin` is the analyzer plugin entrypoint.',
      'The public inspection helpers expose `inspectProviders` and `ProviderMetadata`.',
      'Rules are `missing_route_schema`, `missing_schema_summary`, `missing_schema_response`, `invalid_validation_rule`, and `schema_deprecated_without_description`.',
      'The plugin checks route schema metadata, OpenAPI summaries/responses, pipe validation rule names, and deprecation descriptions.',
    ],
    compose: [
      'Activate it in the application or workspace analysis_options.yaml under `plugins`; adding it only to pubspec dependencies is insufficient.',
      'Restart the analysis server after changing plugin activation.',
      'Keep analyzer-only dependencies and APIs out of runtime provider registration.',
    ],
    pitfalls: [
      'Do not turn a lint into a runtime exception or provider.',
      'Keep rule names stable because analysis_options and CI suppressions refer to them.',
      'When adding a rule, test both the diagnostic location and the non-diagnostic valid form.',
    ],
    tests: 'Run analyzer plugin tests and metadata inspection tests; validate activation with the Dart SDK range >=3.9.0 and an analysis server that supports plugins.',
    quickStart: [
      'plugins:',
      '  routed_analyzer: ^0.1.0',
    ],
  },
  routed_auth: {
    summary: 'Routed HTTP, session, and router integration on top of server_auth. It supplies auth routes, middleware, runtime wiring, and a typed auth store boundary.',
    api: [
      '`AuthServiceProvider` creates and exposes the `AuthRuntime` through `AuthManager`.',
      '`AuthOptions<EngineContext>` carries the typed `AuthStore`, provider list, and feature modules.',
      '`AuthRoutes` owns auth route wiring; `requireAuthenticated()` supplies the session guard middleware.',
      '`SessionAuth`, `jwtAuthentication`, and `oauth2Introspection` provide Routed middleware wrappers.',
      '`Haigate`, `GatePayloadProvider`, and `GateDeniedHandler` bridge authorization gates into the Routed middleware pipeline.',
      'The barrel re-exports server_auth contracts and the auth crypto helpers; persistence is supplied by the application.',
    ],
    compose: [
      'Batteries-included apps register the Routed provider catalogue, then provide `AuthOptions` with an explicit `AuthStore`.',
      'Slim apps add `AuthServiceProvider()` after `Engine.defaultProviders` and register the same typed options.',
      'Use routed_sessions when session-backed authentication needs the session adapter; use server_auth directly for framework-neutral auth runtime work.',
    ],
    pitfalls: [
      'Do not create a persistence store implicitly; `AuthServiceProvider` must use the application-supplied store.',
      'Do not add a second provider registry or untyped provider configuration.',
      'Test unauthenticated, authenticated, invalid-token, callback, and session-update paths whenever middleware or provider wiring changes.',
    ],
    tests: 'Cover provider initialization, route registration, guard behavior, JWT/OAuth wrappers, callback events, session updates, and property-based auth flows.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_auth/routed_auth.dart';",
      "import 'package:server_auth/server_auth.dart';",
      '',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  AuthServiceProvider(),',
      ']);',
      'engine.instance<AuthOptions<EngineContext>>(',
      '  AuthOptions(store: InMemoryAuthStore(), providers: const []),',
      ');',
    ],
  },
  routed_cache: {
    summary: 'The Routed adapter for server_cache. It binds cache stores and DataCacheManager behavior to EngineContext, middleware, events, and a typed provider.',
    api: [
      '`RoutedCacheProvider(CacheConfig(store: ...))` installs the cache store in the engine.',
      '`withCacheManager(DataCacheManager)` supplies the manager option used by the context extension.',
      '`ctx.cache`, `ctx.getCache`, `ctx.removeCache`, `ctx.cacheForever`, `ctx.rememberCache*`, `ctx.incrementCache`, and `ctx.decrementCache` are the request-facing helpers.',
      '`cacheMiddleware(store)` exposes store-oriented helpers such as `ctx.cacheStore` and `ctx.hasCache`.',
      'The adapter re-exports server_cache stores, `DataCacheManager`, `Repository`, cache events, and `CacheConfig`.',
    ],
    compose: [
      'Choose ArrayStore, FileStore, RedisStore, or NullStore in server_cache and pass the selected Store into the provider.',
      'Use the provider for the typed context service and middleware when handlers need store access.',
      'Keep cache algorithms and store implementations in server_cache; keep EngineContext integration here.',
    ],
    pitfalls: [
      '`getCache` has pull semantics in this adapter: it reads and deletes the value. Use a non-pull read API when the value must remain.',
      'Do not silently change serialization, TTL, tag, lock, or increment behavior inherited from server_cache.',
      'Test array/file/redis/null composition only where relevant, and always test expiry and missing-key behavior.',
    ],
    tests: 'Cover context extensions, provider options, cache middleware, events, locks, tags, pull semantics, and store boundary behavior.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_cache/routed_cache.dart';",
      "import 'package:server_cache/server_cache.dart';",
      '',
      'final store = ArrayStore();',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  RoutedCacheProvider(CacheConfig(store: store)),',
      ']);',
      'engine.use(cacheMiddleware(store));',
    ],
  },
  routed_cli: {
    summary: 'The Routed command runtime and project tooling. It owns command registration, project command discovery, development servers, scaffolding, provider commands, route inspection, OpenAPI generation, and deployment orchestration.',
    api: [
      '`RoutedCommandRunner` is the public command runner.',
      '`CliLogger`, `CliVersion`, and `DevOptions` provide shared CLI concerns.',
      '`ProjectCommandsLoader` discovers and proxies application commands.',
      '`DevServerRunner` runs and watches the application development server.',
      '`Templates`, `ScaffoldTemplate`, and `scaffoldTemplateBytes` define project scaffolding.',
      '`ProviderCommandRegistry` and `ProviderArtisanalCommandRegistry` extend provider command surfaces.',
    ],
    compose: [
      'Install as a dev dependency and invoke it with `dart run routed_cli ...`; it is not an Engine provider.',
      'Generated applications keep typed provider configuration in lib/config.dart and routes in lib/app.dart; the CLI loads createEngine().',
      'OpenAPI generation consumes the runtime route manifest; deployment commands consume generated project metadata and provider bindings.',
    ],
    pitfalls: [
      'Preserve dry-run behavior and never write secrets into generated Wrangler or deployment config.',
      'Keep command names and aliases compatible; canonical OpenAPI invocation is `dart run routed_cli openapi generate`.',
      'When changing scaffolding, test generated files, imports, formatting, and the follow-up command execution.',
    ],
    tests: 'Cover create templates, command parsing, project command discovery, dev-server lifecycle, provider command registration, OpenAPI generation, and deployment argument validation.',
    quickStart: [
      'dev_dependencies:',
      '  routed_cli: ^0.3.0',
      '',
      'Run commands with:',
      '  dart run routed_cli create',
      '  dart run routed_cli dev',
      '  dart run routed_cli openapi generate',
    ],
  },
  routed_core: {
    summary: 'The slim HTTP engine foundation: Engine, EngineContext, Router, request/response values, DI/container, lifecycle, providers, middleware, route metadata, and portable transport contracts.',
    api: [
      '`Engine.create()` boots `Engine.defaultProviders`; `Engine` owns routes, middleware, lifecycle, and transport dispatch.',
      '`EngineContext` exposes request-scoped services, response builders, typed state, context keys, and provider services.',
      '`Router`, `RouteBuilder`, controllers, route metadata, and middleware references define the routing surface.',
      '`ServiceProvider`, `TypedProvider`, `CoreServiceProvider`, `RoutingServiceProvider`, and `UploadsServiceProvider` define provider boot.',
      '`PortableRequest`, `PortableResponse`, `RequestAdapter`, `ResponseAdapter`, `ServerTransport`, `Engine.handlePortable`, and `Engine.handleConnection` form the host boundary.',
      'The public barrel also exposes configuration, lifecycle shutdown, network matching, trusted-proxy resolution, websockets, signals, and deep merge/copy utilities.',
    ],
    compose: [
      'Use `Engine.defaultProviders` for a slim core app; append feature providers explicitly.',
      'Keep feature adapters on routed_core plus server_* packages. The core must not import the batteries-included routed facade.',
      'Keep host binding in routed_io, routed_node, or server_native; use the portable value/connection APIs for non-VM hosts.',
    ],
    pitfalls: [
      'Preserve provider ordering and lifecycle events; a provider that depends on another must boot after it.',
      'Do not add feature-specific services, storage, auth, or host sockets to core.',
      'When changing request/response or route contracts, test both direct Engine handling and the affected host adapter.',
    ],
    tests: 'Cover provider boot, routing, middleware order, request/response conversion, context state, route metadata, portable dispatch, websocket/lifecycle behavior, and boundary purity.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      '',
      'final engine = await Engine.create(',
      '  providers: Engine.defaultProviders,',
      ')..get(\'/health\', (ctx) => ctx.json({\'ok\': true}));',
      'await engine.serve(port: 8080);',
    ],
  },
  routed_hotwire: {
    summary: 'Turbo and Stimulus helpers for server-rendered interactive applications. It adds response/request interpretation, Turbo Streams, websocket stream hubs, and context extensions without registering a provider.',
    api: [
      '`TurboRequestKind` and `TurboRequestInfo` classify Turbo frame, stream, navigation, and ordinary requests.',
      '`TurboResponse` and `TurboResponseContext` provide Turbo-aware redirects, frames, flash messages, and response headers.',
      '`TurboStreamAction`, `turboStreamAppend`, and the Turbo Streams helpers create stream responses.',
      '`TurboStreamHub`, `TurboStreamSocketHandler`, `WebSocketTurboConnection`, and `TurboTopicResolver` handle websocket stream delivery.',
      'The package also exposes Stimulus controller scaffolding/assets and testing helpers layered over routed_testing/server_testing.',
    ],
    compose: [
      'Import the package alongside routed or routed_core; the package extends EngineContext and does not add an Engine provider.',
      'Use Turbo response helpers for HTML navigation and stream updates; keep application authorization for stream topics explicit.',
      'Use routed_testing to exercise Turbo headers, stream bodies, optimistic updates, and websocket behavior.',
    ],
    pitfalls: [
      'Do not treat a Turbo request as authorization; validate the user and topic before broadcasting.',
      'Keep stream names stable because browser subscriptions and websocket routing depend on them.',
      'Preserve correct content types and Turbo-specific status/redirect semantics.',
    ],
    tests: 'Cover request classification, stream rendering, append/replace/remove actions, redirects/flash, Stimulus asset output, and websocket hub lifecycle.',
    quickStart: [
      "import 'package:routed/routed.dart';",
      "import 'package:routed_hotwire/routed_hotwire.dart';",
      '',
      'engine.post(\'/notes\', (ctx) => ctx.turboStream(',
      "  turboStreamAppend(target: 'notes', html: '<li>new</li>'),",
      '));',
    ],
  },
  routed_http: {
    summary: 'HTTP request/response utilities layered on routed_core: typed binding, multipart uploads, content negotiation, conditional requests, SSE, proxy handling, and opt-in buffered gzip compression.',
    api: [
      '`ctx.bind`, `ctx.bindJSON`, `ctx.bindQuery`, `ctx.bindForm`, and `ctx.bindMultipart` provide typed request binding.',
      '`QueryBinding`, `JsonBinding`, `FormBinding`, `UriBinding`, `MultipartBinding`, `MultipartForm`, and `MultipartFile` implement binding and upload limits.',
      '`ContentNegotiator`, `ctx.negotiate`, `EtagCandidate`, `ConditionalOutcome`, and conditional helpers implement response negotiation/ETag behavior.',
      '`SseEvent`, `SseCodec`, and `ctx.sse` implement Server-Sent Events.',
      '`CompressionConfig` and `RoutedCompressionProvider` enable buffered gzip for eligible responses.',
      '`ProxyOptions` and the context extensions cover proxy/request helpers; query params, XML, SSE, and binding codecs are public.',
    ],
    compose: [
      'Use directly with routed_core for only HTTP utilities; routed re-exports and registers its official provider.',
      'Add `RoutedCompressionProvider(CompressionConfig(...))` explicitly before engine creation; configuration is typed and fixed for the engine lifetime.',
      'Enforce multipart size, extension, and quota settings at the binding boundary, before writing uploaded content.',
    ],
    pitfalls: [
      'Compression is opt-in, buffered, and not a YAML/dotted-key setting; do not mutate provider configuration after startup.',
      'Preserve negotiation quality/priority and conditional response status semantics.',
      'Test upload rejection, malformed input, content-type mismatch, SSE framing, and gzip eligibility.',
    ],
    tests: 'Cover JSON/form/query/URI/multipart binding, upload guardrails, negotiation, conditional requests, SSE encoding, proxy handling, and compression provider behavior.',
    quickStart: [
      "import 'dart:async';",
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_http/routed_http.dart';",
      '',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  RoutedCompressionProvider(CompressionConfig(enabled: true)),',
      '])..get(\'/events\', (ctx) async {',
      "  await ctx.sse(Stream.value(SseEvent(data: 'ready')));",
      '});',
    ],
  },
  routed_io: {
    summary: 'The dart:io host transport for Routed. It maps HttpRequest/HttpResponse and native socket connections into routed_core transport contracts.',
    api: [
      '`serveIo` and `serveSecureIo` bind a VM HTTP(S) server and return a closeable server handle.',
      '`IoServerTransport`, `IoHttpConnection`, `IoRequestAdapter`, and `IoResponseAdapter` implement native request/response and streaming paths.',
      '`dispatchIoExchange` and `portableRequestFromIo` provide the buffered portable value edge.',
      'The native serve path uses `Engine.handleConnection` for streaming and websocket behavior; `portableEdge: true` forces the buffered path.',
      'The host capability is `HostCapabilities.ioProcess`.',
    ],
    compose: [
      'Depend on routed_core plus routed_io for a Dart VM server.',
      'Use native serve by default; use the portable value edge for custom loops or compatibility paths that need buffered responses.',
      'Keep this package out of Node, Bun, Deno, Workers, Vercel, and Netlify builds.',
    ],
    pitfalls: [
      'Do not move dart:io types into routed_core or feature adapters.',
      'Close the returned server handle and test graceful shutdown.',
      'Test both streaming/native connection and portable buffered dispatch when changing adapters.',
    ],
    tests: 'Cover bind/serve, secure options, request/response adapters, connection streaming, websocket handoff, portable dispatch, and shutdown.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_io/routed_io.dart';",
      '',
      'final engine = await Engine.create(providers: Engine.defaultProviders);',
      "engine.get('/', (ctx) => ctx.string('ok'));",
      "final handle = await serveIo(engine, host: '127.0.0.1', port: 8080);",
      'await handle.close();',
    ],
  },
  routed_logging: {
    summary: 'The HTTP logging provider and request logger surface. It installs RoutedLogger, logging context, driver registration, and stderr/null/file drivers.',
    api: [
      '`LoggingServiceProvider` installs logging services; `registerRoutedLoggingProviders()` registers the package provider catalogue.',
      '`LoggingConfig` controls typed provider configuration such as `errorsOnly`.',
      '`RoutedLogger`, `LoggingContext`, and `ctx.logger` provide request-scoped logging.',
      '`LogDriverRegistry`, `LogDriverRegistration`, `StderrLogDriver`, `NullLogDriver`, and `SingleFileLogDriver` define output drivers.',
      'The package re-exports selected routed_core logging/config contracts needed to integrate the provider.',
    ],
    compose: [
      'The routed facade includes logging after `registerRoutedProviders()`.',
      'A slim engine adds `LoggingServiceProvider()` or a typed `LoggingConfig` instance to its provider list.',
      'Keep driver construction and validation explicit; do not introduce an implicit global logger.',
    ],
    pitfalls: [
      'Configuration is typed and fixed at engine startup; there is no YAML/dotted-key logging path.',
      'Do not leak request secrets or authorization headers into log records.',
      'Preserve errorsOnly and request-context behavior when changing driver dispatch.',
    ],
    tests: 'Cover provider boot, context logger access, driver registration/validation, stderr/null/file output, errorsOnly filtering, and request correlation.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_logging/routed_logging.dart';",
      '',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  LoggingServiceProvider(LoggingConfig(errorsOnly: true)),',
      ']);',
      "engine.get('/health', (ctx) { ctx.logger.info('health'); return ctx.json({'ok': true}); });",
    ],
  },
  routed_node: {
    summary: 'The multi-host JavaScript and edge transport. It supports explicit Node.js, Bun, Deno, Cloudflare Workers, Vercel, and Netlify entrypoints over the same routed_core portable contracts.',
    api: [
      '`serveNode`, `serveBun`, and `serveDeno` run listener hosts.',
      '`cloudflare.dart`, `vercel.dart`, and `netlify.dart` expose Fetch-style bootstrap functions; Cloudflare uses `defineCloudflareFetchAsync`.',
      '`dispatchFetchExchange`, `dispatchFetchConnection`, and `dispatchNodeExchange` map buffered/streaming host requests to Engine portable handlers.',
      '`NodeHttpConnection`, `NodeRequestAdapter`, `NodeResponseAdapter`, and `NodeServerTransport` implement Node streaming and websocket paths.',
      'Cloudflare wrappers expose value-oriented environment, D1, Durable Objects, R2, Queues, service bindings, Workflows, Containers, and execution-context helpers.',
      'Capability differences are intentional: Node/Bun/Deno support listener websockets, Cloudflare supports the Worker websocket bridge, and Vercel/Netlify expose no server-side upgrade API.',
    ],
    compose: [
      'Import only the runtime entrypoint required by the deployment target; do not import routed_io in JavaScript builds.',
      'Use routed_core plus routed_node and keep application route/provider code host-neutral.',
      'Use Cloudflare binding wrappers through the request context; native Dart VM calls report UnsupportedError for unavailable bindings.',
    ],
    pitfalls: [
      'Do not promise websocket support on Vercel or Netlify; route persistent realtime traffic to a supported host/service.',
      'Preserve streaming vs buffered dispatch and Fetch Request/Response semantics.',
      'Test each runtime entrypoint separately, including unsupported-host capability flags and JS compilation.',
    ],
    tests: 'Cover runtime identity, listener lifecycle, Fetch exchange/connection dispatch, Node adapters, websocket upgrades, Cloudflare binding wrappers, and host capability matrices.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_node/node.dart';",
      '',
      'final engine = await Engine.create(providers: Engine.defaultProviders);',
      "final handle = await serveNode(engine, host: '0.0.0.0', port: 8080);",
      'await handle.close();',
    ],
  },
  routed_observability: {
    summary: 'Health, metrics, tracing, and error-observer integration for Routed. It provides one typed provider and services for operational endpoints and telemetry.',
    api: [
      '`ObservabilityServiceProvider` installs observability services and configured middleware.',
      '`ObservabilityConfig` contains tracing, metrics, health, errors, and Sentry configuration objects.',
      '`HealthService`, `HealthCheck`, `HealthCheckResult`, `HealthResponse`, and `HealthEndpointRegistry` implement health checks/endpoints.',
      '`MetricsService` provides counters/histograms; `TracingService` and tracing config integrate OpenTelemetry-compatible spans.',
      '`ErrorObserverRegistry` handles configured error observation; `registerRoutedObservabilityProviders()` registers the default provider.',
      'Default health endpoints are `/readyz` and `/livez`; metrics use `/metrics` when enabled.',
    ],
    compose: [
      'The routed facade registers the provider; slim apps add `ObservabilityServiceProvider(ObservabilityConfig(...))` explicitly.',
      'Configuration is validated before provider boot and fixed for engine lifetime.',
      'Keep telemetry failure isolated from request correctness: an exporter or observer failure must not replace the application response.',
    ],
    pitfalls: [
      'Do not expose health or metrics endpoints without considering access policy and information disclosure.',
      'Preserve disabled-by-default behavior for optional exporters and avoid recording raw sensitive payloads.',
      'Test health failure status, metric cardinality, trace propagation, and observer exception isolation.',
    ],
    tests: 'Cover config validation, provider registration, health readiness/liveness, metrics counters/histograms, trace headers/spans, error observers, and endpoint responses.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_observability/routed_observability.dart';",
      '',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  ObservabilityServiceProvider(ObservabilityConfig(',
      '    metrics: ObservabilityMetricsConfig(enabled: true),',
      '    health: ObservabilityHealthConfig(enabled: true),',
      '  )),',
      ']);',
    ],
  },
  routed_openapi: {
    summary: 'Portable OpenAPI metadata extraction and generation for Routed routes. It enriches RouteBuilder metadata, extracts manifests, and converts them into OpenAPI specs without registering a runtime provider.',
    api: [
      'Fluent `RouteBuilder` extensions include `summary`, `description`, `tags`, `operationId`, `deprecated`, `hidden`, `responseSchema`, `paramSchema`, and `bodySchema` metadata.',
      'Annotations include `Summary`, `Description`, `Tags`, `OperationId`, `ApiDeprecated`, `ApiHidden`, `ApiResponse`, `ApiParam`, and `ApiBody`.',
      '`RouteSchema`, `BodySchema`, `ParamSchema`, and `ResponseSchema` describe route contracts.',
      '`OpenApiSpec` and its path/operation/schema models represent generated output; `OpenApiConfig` controls manifest-to-spec generation.',
      '`OpenApiBuilder`, metadata extraction/merging, handler identity, pipe-rule conversion, and schema validation form the build pipeline.',
    ],
    compose: [
      'Attach metadata to route builders so nested groups and mounted routers carry cumulative prefixes into the manifest.',
      'Use routed_openapi_builder as the dev-time builder and routed_cli to generate the runtime manifest before build_runner.',
      'Keep this package free of runtime provider registration; it reads route metadata rather than booting an Engine service.',
    ],
    pitfalls: [
      'Do not reconstruct route graphs heuristically when the manifest is available.',
      'For dynamic prefixes or inline closures, attach fluent metadata directly for deterministic output.',
      'Preserve nested group prefix flattening, response status codes, hidden/deprecated flags, and validation-to-schema conversion.',
    ],
    tests: 'Cover fluent metadata, annotations, nested groups/mounted routers, schema validation, handler identity, pipe-rule conversion, manifest extraction, and final OpenAPI JSON.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_openapi/routed_openapi.dart';",
      '',
      'final engine = await Engine.create(providers: Engine.defaultProviders);',
      "engine.post('/users', (ctx) => ctx.json({'created': true}, statusCode: 201))",
      "  .summary('Create a user')",
      "  .tags(['Users'])",
      "  .responseSchema(const ResponseSchema(201, description: 'User created'));",
    ],
  },
  routed_openapi_builder: {
    summary: 'The build_runner integration that turns the authoritative Routed route manifest into static OpenAPI artifacts.',
    api: [
      '`OpenApiBuilder` is the public build_runner Builder.',
      'It consumes the runtime route manifest generated by the CLI; it does not scan source code or guess routes.',
      'Outputs are `lib/generated/openapi.json` and `lib/generated/openapi_controller.g.dart`.',
      'Nested groups, mounted routers, controllers, and cumulative prefixes are preserved from the manifest.',
    ],
    compose: [
      'Install as a dev dependency, run `dart run routed_cli openapi generate`, then run `dart run build_runner build --delete-conflicting-outputs`.',
      'Keep runtime engine/provider initialization in the application; this package is never an Engine provider.',
      'Use literal group prefixes and named handlers for strongest annotation/Dartdoc enrichment; use fluent RouteBuilder metadata for dynamic/inline routes.',
    ],
    pitfalls: [
      'Do not add source-code route guessing to the builder; the manifest is authoritative.',
      'Treat generated files as build outputs and test conflict/deletion behavior.',
      'Keep builder output stable so downstream documentation and clients do not churn unnecessarily.',
    ],
    tests: 'Cover builder input discovery, manifest conversion, generated JSON/controller contents, nested prefixes, dynamic metadata, and build_runner integration.',
    quickStart: [
      'dev_dependencies:',
      '  routed_openapi_builder: ^0.1.0',
      '',
      'dart run routed_cli openapi generate',
      'dart run build_runner build --delete-conflicting-outputs',
    ],
  },
  routed_rate_limit: {
    summary: 'The Routed adapter for server_rate_limit. It binds a rate-limit service to EngineContext, a typed provider, middleware, and rate-limit events.',
    api: [
      '`RoutedRateLimitProvider(RateLimitConfig(service: ...))` installs the service.',
      '`rateLimitMiddleware(service)` applies limits to selected routes or middleware stacks.',
      '`RateLimitEngineContext` exposes the service through the request context.',
      'The barrel re-exports server_rate_limit contracts and the Routed rate-limit event types.',
      'Provider IDs and configuration are typed; the full facade can register the official provider.',
    ],
    compose: [
      'Construct the framework-agnostic service in server_rate_limit, then pass it to the provider and middleware.',
      'Use `registerRoutedProviders()` in a batteries-included app or add `RoutedRateLimitProvider` explicitly in a slim engine.',
      'Keep key extraction, window algorithm, storage, and service policy in server_rate_limit.',
    ],
    pitfalls: [
      'Apply middleware at the intended scope; provider installation alone does not necessarily limit every route.',
      'Preserve response headers/status and retry metadata for denied requests.',
      'Test concurrency, reset windows, backend errors, and identity/key normalization.',
    ],
    tests: 'Cover provider config, context access, middleware allow/deny paths, rate-limit events, service backend behavior, and boundary responses.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_rate_limit/routed_rate_limit.dart';",
      "import 'package:server_rate_limit/server_rate_limit.dart';",
      '',
      'final service = RateLimitService(const []);',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  RoutedRateLimitProvider(RateLimitConfig(service: service)),',
      ']);',
      "engine.get('/limited', handler, middlewares: [rateLimitMiddleware(service)]);",
    ],
  },
  routed_security: {
    summary: 'Security providers and primitives for CORS, IP filtering, network matching, trusted proxies, and request-size policy. Security headers and CSRF remain explicit application/middleware concerns.',
    api: [
      '`RoutedSecurityProvider` consumes `RoutedSecurityConfig` and validates all policy values before boot.',
      '`CorsConfig`, `TrustedProxyConfig`, and `IpFilterConfig` configure the provider.',
      '`IpFilter` and `IpFilterAction` implement allow/deny decisions; `NetworkMatcher` and `TrustedProxyResolver` provide reusable primitives.',
      'CORS handles allowed-origin headers and OPTIONS preflight; maxRequestSize enforces request-size policy.',
      '`registerRoutedSecurityProviders()` registers the provider catalogue when composing this package directly.',
    ],
    compose: [
      'Use explicit origins, methods, and headers for credentialed CORS; do not use wildcard origins with credentials.',
      'Enable trusted proxies only for known proxy networks and use the resolver before trusting forwarded client IPs.',
      'Use primitives directly when no provider is needed; configuration is typed and fixed for the engine lifetime.',
    ],
    pitfalls: [
      'Never treat an arbitrary forwarded address as the client IP without trusted-proxy validation.',
      'Do not claim this package supplies CSRF or all security headers; those remain explicit concerns.',
      'Test preflight, denied origin, allow/deny IP boundaries, proxy chains, oversized bodies, and invalid CIDR/header values.',
    ],
    tests: 'Cover config validation, CORS headers/preflight, IP filter actions, network matching, trusted proxy resolution, request-size rejection, and provider boot failures.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_security/routed_security.dart';",
      '',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  RoutedSecurityProvider(RoutedSecurityConfig(',
      "    cors: CorsConfig(enabled: true, allowedOrigins: ['https://app.example']),",
      "    trustedProxies: TrustedProxyConfig(enabled: true, proxies: ['10.0.0.0/8']),",
      '  )),',
      ']);',
    ],
  },
  routed_sessions: {
    summary: 'The Routed adapter for server_sessions. It binds SessionStore behavior to EngineContext, cookies, session middleware, and a typed provider.',
    api: [
      '`RoutedSessionsProvider(SessionConfig(store: ...))` installs the session runtime.',
      '`sessionMiddleware(store)` loads and commits sessions around the request.',
      '`ctx.session`, `ctx.getSession`, `ctx.setSession`, `ctx.clearSession`, and `ctx.sessionId` are the request-facing context helpers.',
      'The barrel re-exports server_sessions contracts such as Session, SessionStore, CookieStore, and MemoryStore.',
      '`SessionConfig` controls the adapter’s framework-facing configuration.',
    ],
    compose: [
      'Construct MemorySessionStore, CookieStore, or another server_sessions store and pass it to both provider/middleware as required by the composition.',
      'Use the same session configuration and cookie policy in production and routed_testing.',
      'Keep session serialization, storage, locking, and expiry behavior in server_sessions.',
    ],
    pitfalls: [
      'Ensure middleware runs before handlers that read/write session state and commits after the response.',
      'Do not expose session identifiers or cookie secrets in logs.',
      'Test missing/expired sessions, clear behavior, concurrent updates, cookie attributes, and response commit failures.',
    ],
    tests: 'Cover provider config, context helpers, middleware load/commit, session store boundaries, cookie handling, expiry, and review-fix regressions.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_sessions/routed_sessions.dart';",
      "import 'package:server_sessions/server_sessions.dart';",
      '',
      'final store = MemorySessionStore();',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  RoutedSessionsProvider(SessionConfig(store: store)),',
      ']);',
      'engine.use(sessionMiddleware(store));',
    ],
  },
  routed_storage: {
    summary: 'The Routed adapter for server_storage. It exposes StorageManager/disks through EngineContext and adds static-file middleware, file-serving extensions, and declarative static mounts.',
    api: [
      '`RoutedStorageProvider(StorageConfig(...))` binds the storage manager/disks to EngineContext.',
      '`StorageConfig`, `ctx.storageManager`, and `ctx.storageDisk` configure/access the runtime.',
      '`storageMiddleware(manager)` provides storage-oriented request helpers.',
      '`RoutedStaticProvider(StaticConfig(...))` registers declarative static mounts with route, disk, path, index, and list_directories options.',
      '`EngineStaticFiles`, `RouterStaticFiles`, and `FileHandlerEngineContext` provide file-serving helpers.',
      'The barrel re-exports server_storage StorageManager, StorageDisk, local/cloud disks, and static file contracts.',
    ],
    compose: [
      'Initialize and await the StorageManager before resolving it from the container; local disks can be configured by RoutedStorageProvider.',
      'Use a supplied StorageDisk for cloud storage; do not assume the provider can create cloud credentials/configuration by itself.',
      'Static mounts support GET/HEAD, index files, optional directory listings, route replacement on config reload, and traversal validation.',
    ],
    pitfalls: [
      'Validate traversal and mount paths before opening a file; never concatenate untrusted path segments without the storage boundary.',
      'Keep static route ownership in routed_storage, not in routed_core or generic feature adapters.',
      'Test missing files, HEAD parity, index/list behavior, traversal rejection, disk selection, and reload replacement.',
    ],
    tests: 'Cover manager initialization, local/cloud disk boundaries, static provider config, GET/HEAD serving, indexes/listings, traversal, middleware, and reload behavior.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_storage/routed_storage.dart';",
      "import 'package:server_storage/server_storage.dart';",
      '',
      "final manager = StorageManager()..registerDisk('local', LocalStorageDisk(root: 'storage/app'))..setDefault('local');",
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      '  RoutedStorageProvider(manager: manager),',
      '  RoutedStaticProvider(StaticConfig(enabled: true, mounts: [',
      "    StaticMountConfig(route: '/assets', disk: 'local'),",
      '  ])),',
      ']);',
    ],
  },
  routed_validation: {
    summary: 'Validation primitives and rule implementations for Routed. It is on-demand and does not register an Engine service provider.',
    api: [
      '`Validator.make(rules, registry: ...)` builds a validator from pipe expressions such as `required|email|min_length:2`.',
      '`ValidationRule`, `AbstractValidationRule`, and `ContextAwareValidationRule` define rule contracts.',
      '`ValidationRuleRegistry`, `ValidationRuleFactory`, `requireValidationRegistry`, and `ValidationContext` manage rule lookup/context.',
      'The public rule catalogue covers required/nullable, string/numeric/array/file rules, comparisons, formats, IP/JSON, and collection rules.',
      '`ValidationFile` and file rules support upload-aware validation without coupling the validator to a concrete filesystem.',
    ],
    compose: [
      'Create the registry on demand from the initialized engine container; there is no provider boot step.',
      'Use routed_validation from a routed app or directly with routed_core request data.',
      'Add a custom rule through the registry/factory contract and keep context-aware rules explicit about required context.',
    ],
    pitfalls: [
      'Preserve rule names and option parsing because routed_analyzer validates pipe rule names statically.',
      'Do not make validation silently mutate input or conflate absent, null, empty, and invalid values.',
      'Test rule messages/options, registry lookup, context-aware behavior, and file metadata limits.',
    ],
    tests: 'Cover validator parsing, registry lookup, scalar/array/file rules, comparison rules, context-aware rules, invalid options, and error collection.',
    quickStart: [
      "import 'package:routed_validation/routed_validation.dart';",
      '',
      "final validator = Validator.make({'email': 'required|email', 'name': 'required|min_length:2'}, registry: ValidationRuleRegistry.defaults());",
      "final errors = validator.validate({'email': 'a@example.com', 'name': 'Ada'});",
    ],
  },
  routed_views: {
    summary: 'View rendering and translation integration for Routed. It owns view engines, provider configuration, locale resolution, translation loading, and EngineContext rendering extensions.',
    api: [
      '`ViewServiceProvider(RoutedViewConfig(...))` installs rendering and `LocalizationServiceProvider(LocalizationConfig(...))` installs translation.',
      '`ctx.template`, `ctx.view`, `ctx.viewTrans`, and `ctx.viewTransChoice` are the main request-facing extensions.',
      '`LiquidViewEngine`, `LiquidRoot`, `ViewEngineManager`, `ViewExtensionRegistry`, and view engine contracts define rendering.',
      '`Translator`, `LocaleManager`, `MessageSelector`, `TranslationLoader`, and `FileTranslationLoader` define translation.',
      '`QueryLocaleResolver`, `CookieLocaleResolver`, `SessionLocaleResolver`, and `HeaderLocaleResolver` resolve request locale.',
      '`registerRoutedViewsProviders()` registers the adapter’s provider catalogue; `kRequestLocaleAttribute` identifies request locale state.',
    ],
    compose: [
      'Pass typed view directory and translation path configuration before engine creation; configuration is fixed for engine lifetime.',
      'Most applications use the routed facade; slim apps add both providers explicitly when they need rendering/localization.',
      'Keep templates, translation files, and locale policy separate; use a custom resolver for application-specific precedence.',
    ],
    pitfalls: [
      'Return a clear TemplateNotFoundException/TemplateRenderException path; do not turn missing templates into silent empty responses.',
      'Avoid locale fallback behavior that ignores explicit request/cookie/session/header precedence.',
      'Test escaping, engine selection, translation parameters/plurals, missing keys, and file loader failures.',
    ],
    tests: 'Cover provider config, Liquid rendering, view/context extensions, custom engines/extensions, locale resolver precedence, translation loading, and message selection.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_views/routed_views.dart';",
      '',
      'final engine = await Engine.create(providers: [',
      '  ...Engine.defaultProviders,',
      "  ViewServiceProvider(RoutedViewConfig(directory: 'views')),",
      "  LocalizationServiceProvider(LocalizationConfig(defaultLocale: 'en')),",
      '])..get(\'/welcome\', (ctx) => ctx.view(\'welcome.liquid\', data: {\'name\': \'Routed\'}));',
    ],
  },
  routed_testing: {
    summary: 'Routed-specific testing helpers built on server_testing. It adapts Engine to in-memory and ephemeral-server transports and exposes property-testing-friendly clients.',
    api: [
      '`RoutedRequestHandler` bootstraps an Engine as a server_testing RequestHandler.',
      '`TransportMode.inMemory` and `TransportMode.ephemeralServer` switch transport without changing the test body.',
      '`TestClient.inMemory(handler)` issues requests through the in-memory adapter; server_testing provides assertions and client behavior.',
      '`TestCallback` and `EngineTestFunction` define reusable engine/client test callbacks.',
      'The adapter re-exports `RoutedTransport` and the testing helpers through both routed_testing.dart and testing.dart.',
    ],
    compose: [
      'Construct the test Engine with the same providers as production; testing helpers do not automatically reproduce feature provider configuration.',
      'Use in-memory tests for fast route/middleware assertions and ephemeralServer for socket/transport integration.',
      'Use property_testing with TestClient to stress route parameters, middleware stacks, and response invariants.',
    ],
    pitfalls: [
      'Always close TestClient, RoutedRequestHandler, and Engine resources.',
      'Do not treat in-memory transport as proof of socket, TLS, streaming, or host-adapter behavior.',
      'Keep test assertions on status/body/headers and add an ephemeral transport case for transport-sensitive changes.',
    ],
    tests: 'Cover handler boot, in-memory requests, ephemeral server lifecycle, provider parity, transport failures, assertions, and property-based route coverage.',
    quickStart: [
      "import 'package:routed_core/routed_core.dart';",
      "import 'package:routed_testing/routed_testing.dart';",
      "import 'package:server_testing/server_testing.dart';",
      '',
      'final engine = await Engine.create();',
      "engine.get('/ping', (ctx) => ctx.text('pong'));",
      'final handler = RoutedRequestHandler(engine);',
      'final client = TestClient.inMemory(handler);',
      "final response = await client.get('/ping');",
      "response.assertStatus(200).assertBodyContains('pong');",
    ],
  },
};

function subsystemDetails(info) {
  return subsystemData[info.name] ?? {
    summary: info.description,
    api: ['Use the public package barrel and the exported API surface shown below.'],
    compose: ['Keep framework integration in this routed package and framework-agnostic behavior in its server_* dependency.'],
    pitfalls: ['Preserve public exports, dependency direction, and existing behavior.'],
    tests: 'Run the focused package tests and add a regression test for changed behavior.',
    quickStart: [`import 'package:${info.name}/${info.name}.dart';`],
  };
}

function skill(info) {
  const skillName = info.name.replaceAll('_', '-');
  const details = subsystemDetails(info);
  const entrypoints = info.libFiles.length === 0
    ? '- No direct `lib/*.dart` public entrypoint; inspect the package before documenting an import.'
    : info.libFiles.map((file) => '- `package:' + info.name + '/' + file + '`').join('\n');
  const packageDependencies = info.dependencyNames.length === 0
    ? '- None declared.'
    : info.dependencyNames.map((name) => '- `' + name + '`').join('\n');
  const testCommand = info.testCount > 0
    ? `dart test ${info.directory}/test`
    : `dart analyze --fatal-infos ${info.directory}`;
  const quickStart = ['```dart', ...details.quickStart, '```'].join('\n');
  return `---
name: ${skillName}
description: Maintain, extend, document, test, or troubleshoot the ${info.name} subsystem in the Routed Dart monorepo. Use when a task touches ${info.name} APIs, implementation, examples, tests, dependency boundaries, or integration with the Routed ecosystem.
---

# ${info.name}

This skill is the complete working guide for the \`${info.name}\` subsystem.
The facts below are intentionally embedded here so the skill can be used
without loading another document.

## Subsystem contract

- **Package:** \`${info.name}\`
- **Directory:** \`${info.directory}\`
- **Version in this checkout:** \`${info.version}\`
- **Role:** ${info.role}
- **Purpose:** ${details.summary}

### Public API

${details.api.map((item) => '- ' + item).join('\n')}

### Public imports

${entrypoints}

### Runtime package dependencies

${packageDependencies}

### Composition rules

${details.compose.map((item) => '- ' + item).join('\n')}

### Known hazards

${details.pitfalls.map((item) => '- ' + item).join('\n')}

## Minimal usage

${quickStart}

## Change workflow

1. Preserve unrelated dirty work and keep changes scoped to \`${info.name}\`.
2. Keep the public import names and exported symbols above stable unless the
   task explicitly changes the API. Never document a \`lib/src\` import.
3. For provider or middleware changes, exercise registration, request-context
   access, the success path, and the failure/reload path.
4. For host or transport changes, test both the value/portable path and the
   streaming/native path where this subsystem supports both.
5. For generated output, make the input contract authoritative and verify the
   generated artifact rather than hand-editing output.
6. Update tests and user-facing package documentation when public behavior
   changes; keep examples aligned with the usage contract above.

### Focused test intent

${details.tests}

## Focused validation

\`\`\`bash
dart format --output=none --set-exit-if-changed ${info.directory}
dart analyze --fatal-infos ${info.directory}
${testCommand}
\`\`\`

Keep this skill's embedded facts synchronized when a public package version,
public barrel, or dependency boundary changes.

## Ecosystem boundary rules

- Applications use \`routed\` for the full provider catalogue or
  \`routed_core\` plus explicit adapters for slim compositions.
- Routed adapters depend on \`routed_core\` and matching \`server_*\` runtimes;
  they must not depend on the batteries-included \`routed\` facade.
- Host I/O belongs in \`routed_io\`, \`routed_node\`, or \`server_native\`, not in
  feature adapters.
- Framework-agnostic \`server_*\` implementations must not import Routed from
  \`lib/\`.
`;
}

function index(infos) {
  const rows = infos.map((info) => {
    const skillName = info.name.replaceAll('_', '-');
    return '| [`' + info.name + '`](./' + info.name + '/SKILL.md) | `' + skillName + '` | `' + info.version + '` | [package](../' + info.directory + ') |';
  });
  return `# Routed subsystem skills

One self-contained skill is maintained for each routed package in this
checkout. Each skill embeds its subsystem API, composition rules, usage
example, hazards, and validation intent.

The generator derives package names, versions, imports, and dependency facts
from manifests and public \`lib/*.dart\` entrypoints, then combines them with
the subsystem-specific contract embedded in the generator. Refresh with:

\`\`\`bash
node tool/generate_routed_skills.mjs
node tool/generate_routed_skills.mjs --check
\`\`\`

| Package | Skill name | Version | Source package |
| --- | --- | --- | --- |
${rows.join('\n')}

## Cross-cutting skills

These skills cover workflows that span multiple Routed packages:

| Skill | Focus |
| --- | --- |
${supplementalSkills.map((skill) => `| [\`${skill.name}\`](./${skill.directory}/SKILL.md) | ${skill.summary} |`).join('\n')}
`;
}

const roles = catalogRoles();
const manifests = walk(packagesRoot, (file, fileName) => fileName === 'pubspec.yaml');
const infos = manifests.map((file) => packageInfo(file, roles)).filter(Boolean).sort((a, b) => a.name.localeCompare(b.name));
const expected = new Map([[path.join(skillsRoot, 'INDEX.md'), index(infos)]]);
for (const info of infos) expected.set(path.join(skillsRoot, info.name, 'SKILL.md'), skill(info));

if (!checkOnly) {
  for (const [file, contents] of expected) {
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, contents);
  }
  console.log(`Generated ${infos.length} routed subsystem skills.`);
} else {
  const failures = [];
  for (const [file, contents] of expected) {
    if (!fs.existsSync(file) || read(file) !== contents) failures.push(path.relative(repoRoot, file));
  }
  const expectedDirectories = new Set([
    ...infos.map((info) => info.name),
    ...supplementalSkills.map((skill) => skill.directory),
  ]);
  if (fs.existsSync(skillsRoot)) {
    for (const entry of fs.readdirSync(skillsRoot, {withFileTypes: true})) {
      if (entry.isDirectory() && entry.name.startsWith('routed_') && !expectedDirectories.has(entry.name)) {
        failures.push(path.relative(repoRoot, path.join(skillsRoot, entry.name)));
      }
    }
  }
  if (failures.length > 0) {
    console.error('Routed subsystem skills are stale or incomplete:');
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.log(`Routed subsystem skills are current (${infos.length} packages checked).`);
}
