import 'package:routed_testing/src/transport/mode.dart';

/// Manages the transport mode within test groups.
class EngineTestEnvironment {
  static final _transportModeStack = <TransportMode>[];

  /// Pushes a transport mode onto the stack.
  static void pushTransportMode(TransportMode mode) {
    _transportModeStack.add(mode);
  }

  /// Pops the top transport mode from the stack.
  static void popTransportMode() {
    if (_transportModeStack.isNotEmpty) {
      _transportModeStack.removeLast();
    }
  }

  /// Retrieves the current transport mode, defaulting to inMemory.
  static TransportMode get currentTransportMode =>
      _transportModeStack.isNotEmpty
          ? _transportModeStack.last
          : TransportMode.inMemory;
}
