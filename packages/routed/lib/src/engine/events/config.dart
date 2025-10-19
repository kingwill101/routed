import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/events/event.dart';

/// Base class for configuration-related events in the engine.
///
/// Configuration events are emitted when the application configuration is loaded,
/// reloaded, or modified. This allows listeners to react to configuration changes
/// at runtime.
///
/// Each event carries the active [config] snapshot along with optional [metadata]
/// that describes the source of the change (e.g., `{"source": "hot-reload"}` or
/// `{"reason": "file-change"}`).
///
/// Example:
/// ```dart
/// eventManager.listen<ConfigLoadedEvent>((event) {
///   final dbUrl = event.config.get('database.url');
///   print('Database URL: $dbUrl');
/// });
/// ```
base class ConfigEvent extends Event {
  /// The configuration instance associated with this event.
  ///
  /// This provides access to all configuration values at the time the event
  /// was emitted.
  final Config config;

  /// Additional metadata describing the event source or context.
  ///
  /// Common metadata keys:
  /// - `source`: Where the configuration change originated (e.g., "file", "api", "hot-reload")
  /// - `reason`: Why the configuration changed (e.g., "startup", "file-change", "manual")
  /// - `timestamp`: When the change occurred
  final Map<String, dynamic> metadata;

  /// Creates a new configuration event.
  ///
  /// The [metadata] parameter is optional and provides additional context about
  /// the configuration change.
  ConfigEvent(this.config, {Map<String, dynamic>? metadata})
    : metadata = metadata ?? const {},
      super();
}

/// Event emitted when configuration is first loaded during engine bootstrap.
///
/// This event fires once during application startup after the configuration
/// has been loaded from files, environment variables, or other sources.
/// Listeners can use this to perform initialization that depends on configuration.
///
/// Example:
/// ```dart
/// eventManager.listen<ConfigLoadedEvent>((event) {
///   final logger = Logger(event.config.get('logging.level'));
///   container.instance<Logger>(logger);
/// });
/// ```
final class ConfigLoadedEvent extends ConfigEvent {
  /// Creates a new configuration loaded event.
  ConfigLoadedEvent(super.config, {super.metadata});
}

/// Event emitted whenever configuration is reloaded or replaced at runtime.
///
/// This event fires when the application configuration is hot-reloaded or
/// programmatically replaced after the initial bootstrap. Listeners can use
/// this to update services or reload resources based on new configuration values.
///
/// Example:
/// ```dart
/// eventManager.listen<ConfigReloadedEvent>((event) {
///   final newTimeout = event.config.get('server.timeout');
///   server.updateTimeout(newTimeout);
/// });
/// ```
final class ConfigReloadedEvent extends ConfigEvent {
  /// Creates a new configuration reloaded event.
  ConfigReloadedEvent(super.config, {super.metadata});
}
