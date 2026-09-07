part of '../routed_jobs.dart';

/// Immutable queue payload exchanged between Routed and a host adapter.
///
/// The representation intentionally mirrors the durable task envelope without
/// exposing the implementation that creates or processes it.
final class JobMessage {
  /// Parses a persisted queue message.
  factory JobMessage.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final args = json['args'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException(
        'Job message id must be a non-empty string',
      );
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException(
        'Job message name must be a non-empty string',
      );
    }
    if (args is! Map) {
      throw const FormatException('Job message args must be an object');
    }
    final normalized = <String, Object?>{};
    for (final entry in args.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'Job message args keys must be strings',
        );
      }
      normalized[entry.key as String] = entry.value;
    }
    final headers = json['headers'];
    final normalizedHeaders = <String, String>{};
    if (headers is Map) {
      for (final entry in headers.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException(
            'Job message headers must be string pairs',
          );
        }
        final key = entry.key as String;
        if (!key.startsWith('stem-')) {
          normalizedHeaders[key] = entry.value as String;
        }
      }
    } else if (headers != null) {
      throw const FormatException('Job message headers must be an object');
    }
    final maxAttempts = _maxAttempts(json);
    final payload = <String, Object?>{
      ...json,
      'id': id,
      'name': name,
      'args': Map<String, Object?>.unmodifiable(normalized),
      'headers': Map<String, String>.unmodifiable(normalizedHeaders),
      'meta': _normalizeMeta(json['meta']),
      'queue': json['queue'] as String? ?? 'default',
      'attempt': (json['attempt'] as num?)?.toInt() ?? 0,
      'maxAttempts': maxAttempts,
      'priority': (json['priority'] as num?)?.toInt() ?? 0,
    };
    return JobMessage._(payload..remove('maxRetries'));
  }

  JobMessage._(Map<String, Object?> payload)
    : _payload = Map<String, Object?>.unmodifiable(payload);

  final Map<String, Object?> _payload;

  /// Stable logical job ID.
  String get id => _payload['id']! as String;

  /// Registered job name.
  String get name => _payload['name']! as String;

  /// Durable job arguments.
  Map<String, Object?> get args =>
      (_payload['args']! as Map).cast<String, Object?>();

  /// Transport headers.
  Map<String, String> get headers => _visibleHeaders(
    (_payload['headers']! as Map).cast<String, String>(),
  );

  /// Application metadata.
  Map<String, Object?> get meta => _visibleMeta(
    (_payload['meta']! as Map).cast<String, Object?>(),
  );

  /// Selected queue.
  String get queue => _payload['queue']! as String;

  /// Zero-based attempt number.
  int get attempt => _payload['attempt']! as int;

  /// Maximum number of deliveries, including the first attempt.
  int get maxAttempts => _payload['maxAttempts']! as int;

  /// Queue priority.
  int get priority => _payload['priority']! as int;

  /// Earliest delivery time, if delayed.
  DateTime? get notBefore => _dateTime('notBefore');

  /// Enqueue timestamp.
  DateTime? get enqueuedAt => _dateTime('enqueuedAt');

  /// Optional visibility timeout.
  Duration? get visibilityTimeout {
    final value = _payload['visibilityTimeout'];
    return value is num ? Duration(milliseconds: value.toInt()) : null;
  }

  /// Serializes this message for a queue adapter.
  Map<String, Object?> toJson() => Map<String, Object?>.from(_payload);

  DateTime? _dateTime(String key) {
    final value = _payload[key];
    return value is String ? DateTime.tryParse(value) : null;
  }

  static Map<String, String> _visibleHeaders(Map<String, String> headers) {
    return Map<String, String>.unmodifiable(
      Map.fromEntries(
        headers.entries.where((entry) => !entry.key.startsWith('stem-')),
      ),
    );
  }

  static Map<String, Object?> _visibleMeta(Map<String, Object?> meta) {
    return Map<String, Object?>.unmodifiable(
      Map.fromEntries(
        meta.entries.where((entry) => !entry.key.startsWith('stem.')),
      ),
    );
  }

  static Map<String, Object?> _normalizeMeta(Object? value) {
    if (value == null) return const <String, Object?>{};
    if (value is! Map) {
      throw const FormatException('Job message meta must be an object');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Job message meta keys must be strings');
      }
      final key = entry.key as String;
      if (!key.startsWith('stem.')) {
        result[key] = entry.value;
      }
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  static int _maxAttempts(Map<String, Object?> json) {
    final value = json['maxAttempts'];
    final attempts = value is num
        ? value.toInt()
        : ((json['maxRetries'] as num?)?.toInt() ?? 0) + 1;
    if (attempts < 1) {
      throw const FormatException('Job message maxAttempts must be at least 1');
    }
    return attempts;
  }
}
