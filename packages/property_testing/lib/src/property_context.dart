import 'package:server_testing/server_testing.dart';

/// A context for property-based testing that provides access to routing infrastructure.
///
/// Contains a [TestClient] for making test requestse.
class PropertyContext {
  /// A test client for making requests against the [engine].
  final TestClient client;

  /// Creates a new [PropertyContext] with the given [client].
  ///
  /// Both [engine] and [client] are required to properly set up the testing context.
  PropertyContext({
    required this.client,
  });
}
