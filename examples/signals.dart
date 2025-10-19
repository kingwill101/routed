import 'package:routed/routed.dart';

/// Demonstrates Routed's signal hub (`SignalHub`) which wraps the event bus with
/// convenient `connect` / `disconnect` hooks and structured error reporting.
///
/// Run with:
/// ```bash
/// dart examples/signals.dart
/// ```
Future<void> main() async {
  final engine = Engine();

  // Define routes before initialization so the routing table is built once.
  final scopedInvocations = <String>[];
  engine
      .get('/scoped', (ctx) async {
        final hub = AppZone.signals;

        late final SignalSubscription<RequestFinishedEvent> subscription;
        subscription = hub.requests.finished.connect(
          (event) async {
            scopedInvocations.add(event.context.request.id);
            await subscription.cancel();
          },
          sender: AppZone.context,
          key: 'scoped-finished',
        );

        return ctx.json({
          'message': 'Scoped handler connected',
          'invocations': List.of(scopedInvocations),
        });
      })
      .name('scoped');
  engine.get('/dashboard', (ctx) => ctx.string('dashboard')).name('dashboard');
  engine.get('/', (ctx) => ctx.string('Signal hub example')).name('home');
  engine.get('/boom', (ctx) => throw UnsupportedError('Kaboom!')).name('boom');

  // Boot providers so EventManager/SignalHub are registered.
  await engine.initialize();

  // Resolve the signal hub. The first resolution wires up listeners to the
  // underlying EventManager and caches the hub in the container.
  final events = await engine.container.make<EventManager>();
  final signals = SignalHub(events);
  engine.container.instance<SignalHub>(signals);

  // Surface handler failures via the normal event bus.
  events.listen<UnhandledSignalError>((event) {
    print(
      '[signal-error] ${event.name} (key=${event.key}) from ${event.sender}: '
      '${event.error}',
    );
  });

  signals.requests.started.connect((event) {
    final request = event.context.request;
    print('[started] ${request.method} ${request.uri.path}');
  }, key: 'logging.started');
  signals.requests.routeMatched.connect((event) {
    print('[matched] ${event.route.name ?? event.route.path}');

    // Demonstrate failure propagation; the listener throws when the "boom"
    // route is matched so the UnhandledSignalError above fires.
    if (event.route.name == 'boom') {
      throw StateError('Route-level instrumentation failed');
    }
  }, key: 'logging.route');

  signals.requests.routingError.connect((event) {
    print('[routing-error] ${event.route.name}: ${event.error}');
  }, key: 'logging.error');

  signals.requests.finished.connect((event) {
    final context = event.context;
    print(
      '[finished] ${context.request.method} ${context.request.uri.path} '
      '-> ${context.response.statusCode}',
    );
  }, key: 'logging.finished');

  final dashboardRoute = engine.getAllRoutes().firstWhere(
    (route) => route.name == 'dashboard',
  );

  // Route-specific listener using EngineRoute sender scoping.
  signals.requests.afterRouting.connect(
    (event) {
      print('[dashboard-after] completed ${event.context.request.path}');
    },
    sender: dashboardRoute,
    key: 'logging.dashboard.after',
  );

  await engine.serve(host: '127.0.0.1', port: 8082);
}
