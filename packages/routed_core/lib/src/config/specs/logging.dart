import 'package:contextual/contextual.dart' as contextual;
import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/provider/typed_provider.dart';

/// A typed logging channel definition.
sealed class LoggingChannelConfig {
  const LoggingChannelConfig({required this.name});

  final String name;
}

/// Writes logs to the process console.
final class ConsoleLoggingChannelConfig extends LoggingChannelConfig {
  const ConsoleLoggingChannelConfig({super.name = 'console'});
}

/// Writes logs to standard output.
final class StdoutLoggingChannelConfig extends LoggingChannelConfig {
  const StdoutLoggingChannelConfig({super.name = 'stdout'});
}

/// Writes logs to standard error.
final class StderrLoggingChannelConfig extends LoggingChannelConfig {
  const StderrLoggingChannelConfig({super.name = 'stderr'});
}

/// Discards log messages.
final class NullLoggingChannelConfig extends LoggingChannelConfig {
  const NullLoggingChannelConfig({super.name = 'null'});
}

/// Writes logs to one file without rotation.
final class SingleFileLoggingChannelConfig extends LoggingChannelConfig {
  const SingleFileLoggingChannelConfig({
    super.name = 'single',
    this.path = 'storage/logs/routed.log',
  });

  final String path;
}

/// Writes logs to daily rotating files.
final class DailyFileLoggingChannelConfig extends LoggingChannelConfig {
  const DailyFileLoggingChannelConfig({
    super.name = 'daily',
    this.path = 'storage/logs/routed',
    this.retentionDays = 14,
    this.flushInterval = const Duration(milliseconds: 500),
    this.useIsolate = false,
  });

  final String path;
  final int retentionDays;
  final Duration flushInterval;
  final bool useIsolate;
}

/// Sends a message to each named channel.
final class StackLoggingChannelConfig extends LoggingChannelConfig {
  StackLoggingChannelConfig({
    super.name = 'stack',
    Iterable<String> channels = const [],
    this.ignoreExceptions = false,
  }) : channels = List<String>.unmodifiable(channels);

  final List<String> channels;
  final bool ignoreExceptions;
}

/// Sends logs to an HTTP webhook.
final class WebhookLoggingChannelConfig extends LoggingChannelConfig {
  const WebhookLoggingChannelConfig({
    required this.url,
    super.name = 'webhook',
    this.headers,
    this.timeout = const Duration(seconds: 5),
    this.keepAlive = true,
  });

  final Uri url;
  final Map<String, String>? headers;
  final Duration timeout;
  final bool keepAlive;
}

/// Samples messages before forwarding them to another channel.
final class SamplingLoggingChannelConfig extends LoggingChannelConfig {
  SamplingLoggingChannelConfig({
    required this.wrappedChannel,
    super.name = 'sampling',
    Map<contextual.Level, double> rates = const {},
  }) : rates = Map<contextual.Level, double>.unmodifiable(rates);

  final String wrappedChannel;
  final Map<contextual.Level, double> rates;
}

/// Configuration for a custom driver registered with the logging driver registry.
///
/// Custom drivers are intentionally the only configuration that accepts an
/// options map. Built-in channels use the typed classes above.
final class CustomLoggingChannelConfig extends LoggingChannelConfig {
  CustomLoggingChannelConfig({
    required this.driver,
    super.name = 'custom',
    Map<String, Object?> options = const {},
  }) : options = Map<String, Object?>.unmodifiable(options);

  final String driver;
  final Map<String, Object?> options;
}

class LoggingFormatConfig {
  LoggingFormatConfig(this.token, this.formatter);

  final String token;
  final contextual.LogMessageFormatter formatter;
}

class LoggingConfig implements ValidatableConfiguration {
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

  final bool enabled;
  final bool errorsOnly;
  final contextual.Level level;
  final Map<String, dynamic> extraFields;
  final List<String> requestHeaders;
  final bool includeStackTraces;
  final LoggingFormatConfig format;
  final String? defaultChannel;
  final Map<String, LoggingChannelConfig> channels;

  bool get logSuccess => !errorsOnly;

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
    name: 'stack',
    channels: const ['single', 'stdout'],
  ),
  'single': const SingleFileLoggingChannelConfig(name: 'single'),
  'daily': const DailyFileLoggingChannelConfig(name: 'daily'),
  'stderr': const StderrLoggingChannelConfig(),
  'stdout': const StdoutLoggingChannelConfig(),
  'null': const NullLoggingChannelConfig(),
};
