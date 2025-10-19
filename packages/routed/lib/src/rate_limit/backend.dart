import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:routed/src/contracts/cache/lock_provider.dart';
import 'package:routed/src/contracts/cache/repository.dart';

import 'policy.dart';

abstract class RateLimiterBackend {
  Future<RateLimitOutcome> consume(
    String bucketKey,
    RateLimitAlgorithmConfig config,
    DateTime now, {
    RateLimitFailoverMode failover,
  });

  Future<void> close();
}

class CacheRateLimiterBackend implements RateLimiterBackend {
  CacheRateLimiterBackend({
    required Repository repository,
    this.lockTimeout = const Duration(seconds: 2),
  }) : _repository = repository,
       _lockProvider = repository.getStore() is LockProvider
           ? repository.getStore() as LockProvider
           : null;

  final Repository _repository;
  final LockProvider? _lockProvider;
  final Duration lockTimeout;
  static const _ttlFloor = Duration(milliseconds: 1000);

  final Map<String, _LocalTokenBucketState> _localTokenBuckets = {};
  final Map<String, _LocalWindowState> _localWindows = {};
  final Map<String, _LocalQuotaState> _localQuotas = {};

  @override
  Future<RateLimitOutcome> consume(
    String bucketKey,
    RateLimitAlgorithmConfig config,
    DateTime now, {
    RateLimitFailoverMode failover = RateLimitFailoverMode.allow,
  }) async {
    final lockProvider = _lockProvider;
    final key = 'rate-limit:$bucketKey';

    Future<RateLimitOutcome> Function() action;
    if (config is TokenBucketConfig) {
      action = () => _consumeTokenBucket(key, config, now);
    } else if (config is SlidingWindowConfig) {
      action = () => _consumeSlidingWindow(key, config, now);
    } else if (config is QuotaConfig) {
      action = () => _consumeQuota(key, config, now);
    } else {
      return RateLimitOutcome.allowed(remaining: 0);
    }

    try {
      if (lockProvider != null) {
        final lock = await lockProvider.lock(
          key,
          max(1, lockTimeout.inSeconds),
        );
        try {
          return await action();
        } finally {
          await lock.release();
        }
      }
      return await action();
    } catch (_) {
      return _handleFailure(bucketKey, config, now, failover);
    }
  }

  Future<RateLimitOutcome> _consumeTokenBucket(
    String key,
    TokenBucketConfig bucket,
    DateTime now,
  ) async {
    final raw = await _repository.get(key);

    var tokens = bucket.maxTokens;
    var timestamp = now.millisecondsSinceEpoch;

    if (raw != null) {
      final state = _decodeState(raw);
      tokens = state.tokens;
      timestamp = state.timestamp;
    }

    final elapsed = now.millisecondsSinceEpoch - timestamp;
    if (elapsed > 0 && bucket.refillPerMillisecond.isFinite) {
      final refill = elapsed * bucket.refillPerMillisecond;
      tokens = min(bucket.maxTokens, tokens + refill);
      timestamp = now.millisecondsSinceEpoch;
    }

    if (tokens >= 1) {
      tokens -= 1;
      await _storeTokenBucketState(key, tokens, timestamp, bucket);
      return RateLimitOutcome.allowed(remaining: tokens.floor());
    }

    if (!bucket.refillPerMillisecond.isFinite ||
        bucket.refillPerMillisecond <= 0) {
      await _storeTokenBucketState(key, tokens, timestamp, bucket);
      return RateLimitOutcome.blocked(
        retryAfter: const Duration(seconds: 1),
        remaining: 0,
      );
    }

    final deficit = 1 - tokens;
    final waitMillis = (deficit / bucket.refillPerMillisecond).ceil();
    await _storeTokenBucketState(key, tokens, timestamp, bucket);
    return RateLimitOutcome.blocked(
      retryAfter: Duration(milliseconds: waitMillis),
      remaining: tokens.floor(),
    );
  }

  Future<RateLimitOutcome> _consumeSlidingWindow(
    String key,
    SlidingWindowConfig config,
    DateTime now,
  ) async {
    final raw = await _repository.get(key);
    final windowMs = max(1, config.window.inMilliseconds);
    final currentWindowStart =
        (now.millisecondsSinceEpoch ~/ windowMs) * windowMs;

    var count = 0;
    if (raw != null) {
      final state = _decodeWindowState(raw);
      if (state.windowStart == currentWindowStart) {
        count = state.count;
      } else if (state.windowStart > 0 &&
          state.windowStart + windowMs > now.millisecondsSinceEpoch) {
        // If we are in-between due to clock drift, clamp to new window.
        count = 0;
      }
    }

    if (count < config.limit) {
      count += 1;
      await _storeWindowState(key, count, currentWindowStart, windowMs);
      return RateLimitOutcome.allowed(remaining: config.limit - count);
    }

    final windowEnd = currentWindowStart + windowMs;
    final retryAfterMs = max(0, windowEnd - now.millisecondsSinceEpoch);
    await _storeWindowState(key, count, currentWindowStart, windowMs);
    return RateLimitOutcome.blocked(
      retryAfter: Duration(milliseconds: retryAfterMs),
      remaining: config.limit - count,
    );
  }

  Future<RateLimitOutcome> _consumeQuota(
    String key,
    QuotaConfig config,
    DateTime now,
  ) async {
    final raw = await _repository.get(key);
    final periodMs = max(1, config.period.inMilliseconds);
    final periodStart = (now.millisecondsSinceEpoch ~/ periodMs) * periodMs;

    var count = 0;
    var storedPeriodStart = periodStart;
    if (raw != null) {
      final state = _decodeQuotaState(raw);
      if (state.periodStart == periodStart) {
        count = state.count;
        storedPeriodStart = state.periodStart;
      }
    }

    if (count < config.limit) {
      count += 1;
      await _storeQuotaState(key, count, periodStart, periodMs);
      return RateLimitOutcome.allowed(remaining: config.limit - count);
    }

    final periodEnd = storedPeriodStart + periodMs;
    final retryAfterMs = max(0, periodEnd - now.millisecondsSinceEpoch);
    await _storeQuotaState(key, count, storedPeriodStart, periodMs);
    return RateLimitOutcome.blocked(
      retryAfter: Duration(milliseconds: retryAfterMs),
      remaining: config.limit - count,
    );
  }

  Future<RateLimitOutcome> _handleFailure(
    String bucketKey,
    RateLimitAlgorithmConfig config,
    DateTime now,
    RateLimitFailoverMode failover,
  ) async {
    switch (failover) {
      case RateLimitFailoverMode.block:
        return RateLimitOutcome.blocked(
          retryAfter: const Duration(seconds: 30),
          remaining: 0,
          failoverMode: RateLimitFailoverMode.block,
        );
      case RateLimitFailoverMode.local:
        return _localConsume(bucketKey, config, now);
      case RateLimitFailoverMode.allow:
        return RateLimitOutcome.allowed(
          remaining: 0,
          failoverMode: RateLimitFailoverMode.allow,
        );
    }
  }

  Future<RateLimitOutcome> _localConsume(
    String bucketKey,
    RateLimitAlgorithmConfig config,
    DateTime now,
  ) async {
    switch (config) {
      case TokenBucketConfig bucket:
        final state = _localTokenBuckets.putIfAbsent(
          bucketKey,
          () => _LocalTokenBucketState(
            tokens: bucket.maxTokens,
            timestamp: now.millisecondsSinceEpoch,
          ),
        );
        final elapsed = now.millisecondsSinceEpoch - state.timestamp;
        if (elapsed > 0 && bucket.refillPerMillisecond.isFinite) {
          final refill = elapsed * bucket.refillPerMillisecond;
          state.tokens = min(bucket.maxTokens, state.tokens + refill);
          state.timestamp = now.millisecondsSinceEpoch;
        }
        if (state.tokens >= 1) {
          state.tokens -= 1;
          return RateLimitOutcome.allowed(
            remaining: state.tokens.floor(),
            failoverMode: RateLimitFailoverMode.local,
          );
        }
        if (!bucket.refillPerMillisecond.isFinite ||
            bucket.refillPerMillisecond <= 0) {
          return RateLimitOutcome.blocked(
            retryAfter: const Duration(seconds: 1),
            remaining: 0,
            failoverMode: RateLimitFailoverMode.local,
          );
        }
        final deficit = 1 - state.tokens;
        final waitMillis = (deficit / bucket.refillPerMillisecond).ceil();
        return RateLimitOutcome.blocked(
          retryAfter: Duration(milliseconds: waitMillis),
          remaining: state.tokens.floor(),
          failoverMode: RateLimitFailoverMode.local,
        );
      case SlidingWindowConfig config:
        final windowMs = max(1, config.window.inMilliseconds);
        final currentWindowStart =
            (now.millisecondsSinceEpoch ~/ windowMs) * windowMs;
        final state = _localWindows.putIfAbsent(
          bucketKey,
          () => _LocalWindowState(count: 0, windowStart: currentWindowStart),
        );
        if (state.windowStart != currentWindowStart) {
          state.windowStart = currentWindowStart;
          state.count = 0;
        }
        if (state.count < config.limit) {
          state.count += 1;
          return RateLimitOutcome.allowed(
            remaining: config.limit - state.count,
            failoverMode: RateLimitFailoverMode.local,
          );
        }
        final windowEnd = currentWindowStart + windowMs;
        final retryAfterMs = max(0, windowEnd - now.millisecondsSinceEpoch);
        return RateLimitOutcome.blocked(
          retryAfter: Duration(milliseconds: retryAfterMs),
          remaining: config.limit - state.count,
          failoverMode: RateLimitFailoverMode.local,
        );
      case QuotaConfig config:
        final periodMs = max(1, config.period.inMilliseconds);
        final periodStart = (now.millisecondsSinceEpoch ~/ periodMs) * periodMs;
        final state = _localQuotas.putIfAbsent(
          bucketKey,
          () => _LocalQuotaState(count: 0, periodStart: periodStart),
        );
        if (state.periodStart != periodStart) {
          state.periodStart = periodStart;
          state.count = 0;
        }
        if (state.count < config.limit) {
          state.count += 1;
          return RateLimitOutcome.allowed(
            remaining: config.limit - state.count,
            failoverMode: RateLimitFailoverMode.local,
          );
        }
        final periodEnd = state.periodStart + periodMs;
        final retryAfterMs = max(0, periodEnd - now.millisecondsSinceEpoch);
        return RateLimitOutcome.blocked(
          retryAfter: Duration(milliseconds: retryAfterMs),
          remaining: config.limit - state.count,
          failoverMode: RateLimitFailoverMode.local,
        );
      default:
        return RateLimitOutcome.allowed(
          remaining: 0,
          failoverMode: RateLimitFailoverMode.local,
        );
    }
  }

  Future<void> _storeTokenBucketState(
    String key,
    double tokens,
    int timestamp,
    TokenBucketConfig bucket,
  ) async {
    final ttl = Duration(
      milliseconds: max(
        bucket.refillInterval.inMilliseconds * 2,
        _ttlFloor.inMilliseconds,
      ),
    );
    final payload = jsonEncode({'tokens': tokens, 'ts': timestamp});
    await _repository.put(key, payload, ttl);
  }

  _StoredState _decodeState(dynamic raw) {
    if (raw is Map) {
      final tokens = (raw['tokens'] is num)
          ? (raw['tokens'] as num).toDouble()
          : double.tryParse(raw['tokens']?.toString() ?? '') ?? 0;
      final timestamp = (raw['ts'] is num)
          ? (raw['ts'] as num).toInt()
          : int.tryParse(raw['ts']?.toString() ?? '') ?? 0;
      return _StoredState(tokens: tokens, timestamp: timestamp);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return _decodeState(decoded);
        }
      } catch (_) {}
    }
    return _StoredState(tokens: 0, timestamp: 0);
  }

  Future<void> _storeWindowState(
    String key,
    int count,
    int windowStart,
    int windowMs,
  ) async {
    final ttl = Duration(
      milliseconds: max(windowMs * 2, _ttlFloor.inMilliseconds),
    );
    final payload = jsonEncode({'count': count, 'window': windowStart});
    await _repository.put(key, payload, ttl);
  }

  Future<void> _storeQuotaState(
    String key,
    int count,
    int periodStart,
    int periodMs,
  ) async {
    final ttl = Duration(
      milliseconds: max(periodMs + _ttlFloor.inMilliseconds, periodMs),
    );
    final payload = jsonEncode({'count': count, 'period': periodStart});
    await _repository.put(key, payload, ttl);
  }

  @override
  Future<void> close() async {
    // No-op: repositories are managed by CacheManager.
  }
}

class _StoredState {
  _StoredState({required this.tokens, required this.timestamp});

  final double tokens;
  final int timestamp;
}

class _WindowState {
  _WindowState({required this.count, required this.windowStart});

  final int count;
  final int windowStart;
}

class _QuotaState {
  _QuotaState({required this.count, required this.periodStart});

  final int count;
  final int periodStart;
}

_WindowState _decodeWindowState(dynamic raw) {
  if (raw is Map) {
    final count = (raw['count'] is num)
        ? (raw['count'] as num).toInt()
        : int.tryParse(raw['count']?.toString() ?? '') ?? 0;
    final window = (raw['window'] is num)
        ? (raw['window'] as num).toInt()
        : int.tryParse(raw['window']?.toString() ?? '') ?? 0;
    return _WindowState(count: max(0, count), windowStart: window);
  }
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _decodeWindowState(decoded);
      }
    } catch (_) {}
  }
  return _WindowState(count: 0, windowStart: 0);
}

_QuotaState _decodeQuotaState(dynamic raw) {
  if (raw is Map) {
    final count = (raw['count'] is num)
        ? (raw['count'] as num).toInt()
        : int.tryParse(raw['count']?.toString() ?? '') ?? 0;
    final period = (raw['period'] is num)
        ? (raw['period'] as num).toInt()
        : int.tryParse(raw['period']?.toString() ?? '') ?? 0;
    return _QuotaState(count: max(0, count), periodStart: period);
  }
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _decodeQuotaState(decoded);
      }
    } catch (_) {}
  }
  return _QuotaState(count: 0, periodStart: 0);
}

class _LocalTokenBucketState {
  _LocalTokenBucketState({required this.tokens, required this.timestamp});

  double tokens;
  int timestamp;
}

class _LocalWindowState {
  _LocalWindowState({required this.count, required this.windowStart});

  int count;
  int windowStart;
}

class _LocalQuotaState {
  _LocalQuotaState({required this.count, required this.periodStart});

  int count;
  int periodStart;
}
