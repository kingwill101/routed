import 'package:routed_core/routed_core.dart';

import 'process_args.dart';

/// Supplies the process environment exposed by a Node-family host.
///
/// The returned value is a snapshot. Application configuration can pass it to
/// [RuntimeContext] when it needs host values during provider validation, while
/// generated Node entrypoints use the same snapshot for CLI arguments and
/// listener defaults.
final class NodeRuntimeEnvironment implements RuntimeEnvironmentSource {
  /// Creates a Node runtime environment source.
  const NodeRuntimeEnvironment();

  /// Reads a fresh snapshot from the current host.
  static RuntimeEnvironment current() =>
      const NodeRuntimeEnvironment().snapshot();

  @override
  RuntimeEnvironment snapshot() => RuntimeEnvironment(
    readProcessEnvironment(),
    arguments: readNodeProcessArguments(),
    isWindows: hostIsWindows,
  );
}
