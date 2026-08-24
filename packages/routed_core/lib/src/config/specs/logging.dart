import 'package:contextual/contextual.dart' as contextual;
import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/provider/typed_provider.dart';

/// A typed logging channel definition.
sealed class LoggingChannelConfig {
  const LoggingChannelConfig({required this.name});

  /// The name used to reference this channel from other configuration values.
  final String name;
}

/// Writes logs to the process console.
final class ConsoleLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a console channel with the default name `console`.
  const ConsoleLoggingChannelConfig({super.name = 'console'});
}

/// Writes logs to standard output.
final class StdoutLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a standard-output channel with the default name `stdout`.
  const StdoutLoggingChannelConfig({super.name = 'stdout'});
}

/// Writes logs to standard error.
final class StderrLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a standard-error channel with the default name `stderr`.
  const StderrLoggingChannelConfig({super.name = 'stderr'});
}

/// Discards log messages.
final class NullLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a channel that discards log messages.
  const NullLoggingChannelConfig({super.name = 'null'});
}

/// Writes logs to one file without rotation.
final class SingleFileLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a single-file channel using [path].
  const SingleFileLoggingChannelConfig({
    super.name = 'single',
    this.path = 'storage/logs/routed.log',
  });

  /// The file path receiving log output.
  final String path;
}

/// Writes logs to daily rotating files.
final class DailyFileLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a daily rotating file channel.
  const DailyFileLoggingChannelConfig({
    super.name = 'daily',
    this.path = 'storage/logs/routed',
    this.retentionDays = 14,
    this.flushInterval = const Duration(milliseconds: 500),
    this.useIsolate = false,
  });

  /// The directory or filename prefix used for rotated log files.
  final String path;

  /// The number of daily log files to retain.
  final int retentionDays;

  /// The maximum interval between writes being flushed to disk.
  final Duration flushInterval;

  /// Whether file writes should be performed in a worker isolate.
  final bool useIsolate;
}

/// Sends a message to each named channel.
final class StackLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a channel that forwards messages to [channels].
  StackLoggingChannelConfig({
    super.name = 'stack',
    Iterable<String> channels = const [],
    this.ignoreExceptions = false,
  }) : channels = List<String>.unmodifiable(channels);

  /// The channel names that receive each message.
  final List<String> channels;

  /// Whether failures in a child channel should be ignored.
  final bool ignoreExceptions;
}

/// Sends logs to an HTTP webhook.
final class WebhookLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a channel that posts messages to [url].
  const WebhookLoggingChannelConfig({
    required this.url,
    super.name = 'webhook',
    this.headers,
    this.timeout = const Duration(seconds: 5),
    this.keepAlive = true,
  });

  /// The webhook endpoint that receives log messages.
  final Uri url;

  /// Additional headers sent with each webhook request.
  final Map<String, String>? headers;

  /// The maximum time allowed for a webhook request.
  final Duration timeout;

  /// Whether the HTTP connection should be reused between requests.
  final bool keepAlive;
}

/// Samples messages before forwarding them to another channel.
final class SamplingLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a channel that samples messages before forwarding them.
  SamplingLoggingChannelConfig({
    required this.wrappedChannel,
    super.name = 'sampling',
    Map<contextual.Level, double> rates = const {},
  }) : rates = Map<contextual.Level, double>.unmodifiable(rates);

  /// The channel that receives sampled messages.
  final String wrappedChannel;

  /// The proportion of messages retained for each log level.
  final Map<contextual.Level, double> rates;
}

/// Configuration for a custom driver registered with the logging driver registry.
///
/// Custom drivers are intentionally the only configuration that accepts an
/// options map. Built-in channels use the typed classes above.
final class CustomLoggingChannelConfig extends LoggingChannelConfig {
  /// Creates a channel backed by the registered [driver].
  CustomLoggingChannelConfig({
    required this.driver,
    super.name = 'custom',
    Map<String, Object?> options = const {},
  }) : options = Map<String, Object?>.unmodifiable(options);

  /// The registered logging driver name.
  final String driver;

  /// Driver-specific options.
  final Map<String, Object?> options;
}

/// Selects the formatter token and formatter used for log messages.
class LoggingFormatConfig {
  /// Creates a format configuration with [token] and [formatter].
  LoggingFormatConfig(this.token, this.formatter);

  /// The stable token identifying this format.
  final String token;

  /// The formatter that renders log messages.
  final contextual.LogMessageFormatter formatter;
}

/// Configures logging, formatting, and output channels for an application.
class LoggingConfig implements ValidatableConfiguration {
  /// Creates logging configuration with production-oriented defaults.
  LoggingConfig({
    this.enabled = true,
    this.errorsOnly = false,
    this.level = contextual.Level.info,
    Map<String, dynamic>? extraFields,
    List<String>? requestHeaders,
    this.includeStackTraces = false,
    LoggingFormatConfig? format,
    Map<String, LoggingChannelConfig>? channels,
    this.defaultChannel = 'stack',
  }) : extraFields = Map<String, dynamic>.unmodifiable(
         extraFields ?? const <String, dynamic>{},
       ),
       requestHeaders = List<String>.unmodifiable(requestHeaders ?? const []),
       format =
           format ??
           LoggingFormatConfig('pretty', contextual.PrettyLogFormatter()),
       channels = Map<String, LoggingChannelConfig>.unmodifiable(
         channels ?? _defaultTypedLoggingChannels(),
       );

  /// Whether application logging is enabled.
  final bool enabled;

  /// Whether only error-level messages should be emitted.
  final bool errorsOnly;

  /// The minimum log level accepted by the configured channels.
  final contextual.Level level;

  /// Additional fields included in structured log records.
  final Map<String, dynamic> extraFields;

  /// Request header names copied into request-related log records.
  final List<String> requestHeaders;

  /// Whether error records include their stack traces.
  final bool includeStackTraces;

  /// The formatter used to render log messages.
  final LoggingFormatConfig format;

  /// The channel used when a log call does not select one explicitly.
  final String? defaultChannel;

  /// The channels available to the logging provider.
  final Map<String, LoggingChannelConfig> channels;

  /// Whether messages below the error level are also eligible for logging.
  bool get logSuccess => !errorsOnly;

  /// Validates channel names, references, and file settings.
  @override
  void validate(ConfigValidationContext context) {
    final configuredChannels = channels;
    if (defaultChannel != null) {
      context.require(
        defaultChannel!.trim().isNotEmpty,
        'defaultChannel',
        'default channel cannot be empty',
      );
      context.require(
        configuredChannels.containsKey(defaultChannel),
        'defaultChannel',
        'default channel must name a configured channel',
      );
    }
    for (final entry in channels.entries) {
      final name = entry.key;
      final channel = entry.value;
      context.require(
        name.trim().isNotEmpty,
        'channels.$name',
        'channel names cannot be empty',
      );
      context.require(
        channel.name.trim().isNotEmpty,
        'channels.$name.name',
        'channel names cannot be empty',
      );
      context.require(
        name == channel.name,
        'channels.$name.name',
        'channel name must match its map key',
      );
      _validateChannel(context, name, channel);
      switch (channel) {
        case StackLoggingChannelConfig(:final channels):
          for (var index = 0; index < channels.length; index++) {
            context.require(
              configuredChannels.containsKey(channels[index]),
              'channels.$name.channels[$index]',
              'referenced channel must be configured',
            );
          }
        case SamplingLoggingChannelConfig(:final wrappedChannel):
          context.require(
            configuredChannels.containsKey(wrappedChannel),
            'channels.$name.wrappedChannel',
            'wrapped channel must be configured',
          );
        default:
          break;
      }
    }
    for (var index = 0; index < requestHeaders.length; index++) {
      context.require(
        requestHeaders[index].trim().isNotEmpty,
        'requestHeaders[$index]',
        'request header names cannot be empty',
      );
    }
  }
}

void _validateChannel(
  ConfigValidationContext context,
  String name,
  LoggingChannelConfig channel,
) {
  final validationPath = 'channels.$name';
  switch (channel) {
    case ConsoleLoggingChannelConfig():
    case StdoutLoggingChannelConfig():
    case StderrLoggingChannelConfig():
    case NullLoggingChannelConfig():
      break;
    case SingleFileLoggingChannelConfig(:final path):
      context.require(
        path.trim().isNotEmpty,
        '$validationPath.path',
        'file path cannot be empty',
      );
    case DailyFileLoggingChannelConfig(
      :final path,
      :final retentionDays,
      :final flushInterval,
    ):
      context.require(
        path.trim().isNotEmpty,
        '$validationPath.path',
        'directory path cannot be empty',
      );
      context.require(
        retentionDays > 0,
        '$validationPath.retentionDays',
        'retention days must be greater than zero',
      );
      context.require(
        flushInterval >= Duration.zero,
        '$validationPath.flushInterval',
        'flush interval cannot be negative',
      );
    case StackLoggingChannelConfig(:final channels):
      context.require(
        channels.isNotEmpty,
        '$validationPath.channels',
        'stack channel must include at least one channel',
      );
      for (var index = 0; index < channels.length; index++) {
        context.require(
          channels[index].trim().isNotEmpty,
          '$validationPath.channels[$index]',
          'channel names cannot be empty',
        );
      }
    case WebhookLoggingChannelConfig(:final url, :final timeout):
      context.require(
        url.hasScheme && url.host.isNotEmpty,
        '$validationPath.url',
        'webhook URL must include a host',
      );
      context.require(
        timeout >= Duration.zero,
        '$validationPath.timeout',
        'timeout cannot be negative',
      );
    case SamplingLoggingChannelConfig(:final wrappedChannel, :final rates):
      context.require(
        wrappedChannel.trim().isNotEmpty,
        '$validationPath.wrappedChannel',
        'wrapped channel cannot be empty',
      );
      for (final entry in rates.entries) {
        context.require(
          entry.value >= 0 && entry.value <= 1,
          '$validationPath.rates.${entry.key.name}',
          'sampling rates must be between zero and one',
        );
      }
    case CustomLoggingChannelConfig(:final driver):
      context.require(
        driver.trim().isNotEmpty,
        '$validationPath.driver',
        'custom driver cannot be empty',
      );
  }
}

Map<String, LoggingChannelConfig> _defaultTypedLoggingChannels() => {
  'stack': StackLoggingChannelConfig(
    channels: const ['single', 'stdout'],
  ),
  'single': const SingleFileLoggingChannelConfig(),
  'daily': const DailyFileLoggingChannelConfig(),
  'stderr': const StderrLoggingChannelConfig(),
  'stdout': const StdoutLoggingChannelConfig(),
  'null': const NullLoggingChannelConfig(),
};
