# routed_node

Node.js host transport for **Routed**.

Maps Node `IncomingMessage` / `ServerResponse` into core portable messages.
Kept separate from **`routed_core`** and **`routed_io`**.

See [portable-host-architecture.md](../../docs/portable-host-architecture.md).

## Paths

| Path | API |
|------|-----|
| **Value edge (preferred)** | `dispatchNodeExchange` → `Engine.handlePortable` |
| Stream sink | `NodeHttpConnection` → `Engine.handleConnection` |
| Bind/listen | `serveNode` / `NodeServerTransport` (JS host only) |

| Core type | Node helper |
|-----------|-------------|
| `PortableRequest` | `portableRequestFromNode` |
| `PortableResponse` | `writePortableResponseToNode` |
| `RequestAdapter` | `NodeRequestAdapter` |
| `ResponseAdapter` | `NodeResponseAdapter` |
| `HttpConnection` | `NodeHttpConnection` |

## Install

```yaml
dependencies:
  routed_core: ^0.3.3
  routed_node: ^0.1.0
```

## Usage (portable exchange)

Works on the Dart VM with fakes; same API for real Node views:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_node/routed_node.dart';

Future<void> onNodeRequest(
  NodeIncomingView req,
  NodeServerResponseView res,
) async {
  await dispatchNodeExchange(
    engine,
    req,
    res,
    baseUri: Uri.parse('http://0.0.0.0:8080'),
  );
}
```

## Usage (serveNode)

```dart
final handle = await serveNode(engine, host: '0.0.0.0', port: 8080);
await handle.close();
```

**Runtime note:** bind/listen uses JS interop (`node:http`). On the Dart VM
`serveNode` throws `UnsupportedError` — use **`package:routed_io`** for VM
process hosting. Full Node deploy still needs a JS-capable core build over time.

Declared capabilities: `HostCapabilities.nodeProcess`.

## Testing on Node

```bash
cd packages/routed_node
dart test -p vm      # default
dart test -p node    # dart2js + Node (Engine portable path supported)
```

## Sample API project

Runnable JSON API under **`example/api/`** (routes, smoke on the Dart VM,
`serveNode` entry + Node bootstrap):

```bash
cd packages/routed_node/example/api
dart pub get
dart run bin/smoke.dart          # same handlers, no Node
# Node (when dart2js of the engine succeeds):
# npm run build && npm start
```

See [example/api/README.md](example/api/README.md).

## See also

- [`routed_io`](../routed_io) — `dart:io` host
- [`routed_core`](../routed_core) — engine + portable types
- [package-boundary-contract.md](../../docs/package-boundary-contract.md)
