
import 'package:contextual/contextual.dart';
import 'package:path/path.dart' as path;

/// Logger used by browser page/component helpers.
///
/// Wraps the `contextual` Logger to provide structured output while
/// maintaining the existing convenience API for browser interactions.
class EnhancedBrowserLogger {
  final bool verboseLogging;
  final String? logDirectory;
  final bool enabled;
  final Logger? _logger;

  EnhancedBrowserLogger({
    this.verboseLogging = false,
    this.logDirectory,
    this.enabled = true,
  }) : _logger = enabled
           ? (Logger(
               environment: verboseLogging ? 'development' : 'test',
               formatter: verboseLogging
                   ? PrettyLogFormatter()
                   : PlainTextLogFormatter(),
             )..addChannel('console', ConsoleLogDriver()))
           : null {
    if (enabled && logDirectory != null) {
      final basePath = path.join(logDirectory!, 'browser_test');
      _logger?.addChannel('file', DailyFileLogDriver(basePath));
    }
  }

  void logInfo(
    String message, {
    String? action,
    String? selector,
    String? details,
    Context? context,
  }) {
    if (!enabled || !verboseLogging) return;
    _logger?.info(
      message,
      _buildContext(action, selector, details, null, null, context: context),
    );
  }

  void logWarning(
    String message, {
    String? action,
    String? selector,
    String? details,
    Context? context,
  }) {
    if (!enabled) return;
    _logger?.warning(
      message,
      _buildContext(action, selector, details, null, null, context: context),
    );
  }

  void logError(
    String message, {
    String? action,
    String? selector,
    String? details,
    dynamic error,
    Context? context,
  }) {
    if (!enabled) return;
    _logger?.error(
      message,
      _buildContext(
        action,
        selector,
        details,
        null,
        null,
        error: error,
        context: context,
      ),
    );
  }

  void logOperationStart(
    String action, {
    String? selector,
    Map<String, dynamic>? parameters,
    Context? context,
  }) {
    if (!enabled || !verboseLogging) return;
    _logger?.info(
      'Starting $action',
      _buildContext(action, selector, null, parameters, null, context: context),
    );
  }

  void logOperationComplete(
    String action, {
    String? selector,
    Duration? duration,
    Context? context,
  }) {
    if (!enabled || !verboseLogging) return;
    _logger?.info(
      'Completed $action',
      _buildContext(action, selector, null, null, duration, context: context),
    );
  }

  Context _buildContext(
    String? action,
    String? selector,
    String? details,
    Map<String, dynamic>? parameters,
    Duration? duration, {
    dynamic error,
    Context? context,
  }) {
    final data = <String, dynamic>{};

    if (action != null) data['action'] = action;
    if (selector != null) data['selector'] = selector;
    if (details != null) data['details'] = details;
    if (parameters != null && parameters.isNotEmpty) {
      data['parameters'] = parameters;
    }
    if (duration != null) {
      data['durationMs'] = duration.inMilliseconds;
    }
    if (error != null) {
      data['error'] = error.toString();
    }

    final merged = Context(data);
    if (context != null) {
      merged.addAll(context.all());
    }

    return merged;
  }
}
