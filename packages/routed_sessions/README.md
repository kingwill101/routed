# routed_sessions

Routed adapter for [`server_sessions`](https://github.com/kingwill101/routed/tree/master/packages/server_sessions) — framework-agnostic session runtime (`Session`, `SessionStore`, `CookieStore`, `MemoryStore`).

Wraps `server_sessions` for `routed` `EngineContext.session` (`ctx.session`, `ctx.getSession`/`setSession`, `ctx.sessionId`) and `sessionMiddleware`/`RoutedSessionsProvider`.

## Install

```yaml
dependencies:
  routed: ^0.3.3
  routed_sessions: ^0.1.0
  server_sessions: ^0.1.0
```

## Usage

```dart
import 'package:routed/routed.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:server_sessions/server_sessions.dart';

void main() async {
  final store = MemorySessionStore();
  final engine = Engine();
  engine.use(sessionMiddleware(store));

  engine.get('/', (ctx) {
    ctx.setSession('user', 'alice');
    return ctx.json({'sessionId': ctx.sessionId, 'user': ctx.getSession('user')});
  });

  engine.get('/clear', (ctx) {
    ctx.clearSession();
    return ctx.json({'cleared': true});
  });

  await engine.serve(port: 8080);
}
```

See [`example/sessions_example.dart`](example/sessions_example.dart).

## Testing

```bash
dart test packages/routed_sessions
dart analyze --fatal-infos packages/routed_sessions/lib
```
