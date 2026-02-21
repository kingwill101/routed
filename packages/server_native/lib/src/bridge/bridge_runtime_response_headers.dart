part of 'bridge_runtime.dart';

/// Mutable response headers optimized for the bridge write path.
///
/// This implementation keeps both normalized and original casing for names,
/// tracks flattened pair count for preallocation, and mirrors selected typed
/// fields (`contentType`, `contentLength`, connection semantics) to avoid
/// reparsing when adapters query them.
final class _BridgeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = <String, List<String>>{};
  final Map<String, String> _originalNames = <String, String>{};
  final Set<String> _noFolding = <String>{HttpHeaders.setCookieHeader};
  int _flattenedHeaderValueCount = 0;

  DateTime? _date;
  DateTime? _expires;
  DateTime? _ifModifiedSince;
  String? _host;
  int? _port;
  ContentType? _contentType;
  int _contentLength = -1;
  bool _persistentConnection = true;
  bool _chunkedTransferEncoding = false;

  @override
  DateTime? get date => _date;

  @override
  set date(DateTime? value) {
    _date = value;
    _setSingleValue(
      HttpHeaders.dateHeader,
      value == null ? null : HttpDate.format(value),
    );
  }

  @override
  DateTime? get expires => _expires;

  @override
  set expires(DateTime? value) {
    _expires = value;
    _setSingleValue(
      HttpHeaders.expiresHeader,
      value == null ? null : HttpDate.format(value),
    );
  }

  @override
  DateTime? get ifModifiedSince => _ifModifiedSince;

  @override
  set ifModifiedSince(DateTime? value) {
    _ifModifiedSince = value;
    _setSingleValue(
      HttpHeaders.ifModifiedSinceHeader,
      value == null ? null : HttpDate.format(value),
    );
  }

  @override
  String? get host => _host;

  @override
  set host(String? value) {
    _host = value;
    _updateHostHeader();
  }

  @override
  int? get port => _port;

  @override
  set port(int? value) {
    _port = value;
    _updateHostHeader();
  }

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _contentType = value;
    _setSingleValue(HttpHeaders.contentTypeHeader, value?.toString());
  }

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    _contentLength = value;
    if (value < 0) {
      _setSingleValue(HttpHeaders.contentLengthHeader, null);
      return;
    }
    _setSingleValue(HttpHeaders.contentLengthHeader, value.toString());
  }

  @override
  bool get persistentConnection => _persistentConnection;

  @override
  set persistentConnection(bool value) {
    _persistentConnection = value;
    if (value) {
      remove(HttpHeaders.connectionHeader, 'close');
      return;
    }
    _setSingleValue(HttpHeaders.connectionHeader, 'close');
  }

  @override
  bool get chunkedTransferEncoding => _chunkedTransferEncoding;

  @override
  set chunkedTransferEncoding(bool value) {
    _chunkedTransferEncoding = value;
    if (value) {
      _setSingleValue(HttpHeaders.transferEncodingHeader, 'chunked');
      return;
    }
    remove(HttpHeaders.transferEncodingHeader, 'chunked');
  }

  @override
  List<String>? operator [](String name) {
    final values = _headers[_normalize(name)];
    if (values == null) {
      return null;
    }
    return List<String>.from(values);
  }

  @override
  String? value(String name) {
    final values = _headers[_normalize(name)];
    if (values == null || values.isEmpty) {
      return null;
    }
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.first;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    final normalized = _normalize(name);
    final values = _headers.putIfAbsent(normalized, () => <String>[]);
    var addedCount = 0;
    if (value is Iterable<Object?> && value is! String) {
      for (final item in value) {
        values.add(_valueToString(item));
        addedCount++;
      }
    } else {
      values.add(_valueToString(value));
      addedCount = 1;
    }
    if (addedCount == 0) {
      return;
    }
    _flattenedHeaderValueCount += addedCount;
    _originalNames[normalized] = preserveHeaderCase ? name : normalized;
    _updateComputedFields(normalized);
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    final normalized = _normalize(name);
    final previous = _headers[normalized];
    if (previous != null) {
      _flattenedHeaderValueCount -= previous.length;
    }
    _headers.remove(normalized);
    _originalNames.remove(normalized);
    add(name, value, preserveHeaderCase: preserveHeaderCase);
  }

  @override
  void remove(String name, Object value) {
    final normalized = _normalize(name);
    final values = _headers[normalized];
    if (values == null) {
      return;
    }
    final toRemove = _valueToString(value);
    final before = values.length;
    values.removeWhere((element) => element == toRemove);
    final removed = before - values.length;
    if (removed > 0) {
      _flattenedHeaderValueCount -= removed;
    }
    if (values.isEmpty) {
      _headers.remove(normalized);
      _originalNames.remove(normalized);
    }
    _updateComputedFields(normalized);
  }

  @override
  void removeAll(String name) {
    final normalized = _normalize(name);
    final removed = _headers[normalized]?.length ?? 0;
    _flattenedHeaderValueCount -= removed;
    _headers.remove(normalized);
    _originalNames.remove(normalized);
    _updateComputedFields(normalized);
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    for (final entry in _headers.entries) {
      action(
        _originalNames[entry.key] ?? entry.key,
        List<String>.from(entry.value),
      );
    }
  }

  @override
  void noFolding(String name) {
    _noFolding.add(_normalize(name));
  }

  @override
  void clear() {
    _headers.clear();
    _originalNames.clear();
    _noFolding.clear();
    _flattenedHeaderValueCount = 0;
    _date = null;
    _expires = null;
    _ifModifiedSince = null;
    _host = null;
    _port = null;
    _contentType = null;
    _contentLength = -1;
    _persistentConnection = true;
    _chunkedTransferEncoding = false;
  }

  /// Total number of flattened header pairs (including repeated values).
  int get flattenedHeaderValueCount {
    return _flattenedHeaderValueCount;
  }

  /// Total number of serialized header pairs after folding rules are applied.
  int get flattenedHeaderPairCount {
    var count = 0;
    for (final entry in _headers.entries) {
      if (entry.key == HttpHeaders.transferEncodingHeader) {
        continue;
      }
      final values = entry.value;
      if (values.isEmpty) {
        continue;
      }
      if (_shouldFoldHeader(entry.key)) {
        count += 1;
      } else {
        count += values.length;
      }
    }
    return count;
  }

  /// Writes all header pairs into [headerNames]/[headerValues] from [offset].
  int writeFlattenedHeaderPairs(
    List<String> headerNames,
    List<String> headerValues,
    int offset,
  ) {
    for (final entry in _headers.entries) {
      if (entry.key == HttpHeaders.transferEncodingHeader) {
        continue;
      }
      final originalName = _originalNames[entry.key] ?? entry.key;
      final values = entry.value;
      if (values.isEmpty) {
        continue;
      }
      if (_shouldFoldHeader(entry.key)) {
        headerNames[offset] = originalName;
        headerValues[offset] = values.length == 1
            ? values.first
            : values.join(', ');
        offset++;
        continue;
      }
      for (var i = 0; i < values.length; i++) {
        headerNames[offset] = originalName;
        headerValues[offset] = values[i];
        offset++;
      }
    }
    return offset;
  }

  @pragma('vm:prefer-inline')
  bool _shouldFoldHeader(String normalizedName) {
    return !_noFolding.contains(normalizedName);
  }

  @pragma('vm:prefer-inline')
  String _normalize(String name) {
    if (name.isEmpty) {
      throw ArgumentError('Header name cannot be empty');
    }
    return _asciiLower(name);
  }

  @pragma('vm:prefer-inline')
  String _valueToString(Object? value) {
    if (value is DateTime) {
      return HttpDate.format(value);
    }
    if (value is HeaderValue) {
      return value.toString();
    }
    if (value is ContentType) {
      return value.toString();
    }
    return value.toString();
  }

  @pragma('vm:prefer-inline')
  void _setSingleValue(String name, String? value) {
    final normalized = _normalize(name);
    final previousLength = _headers[normalized]?.length ?? 0;
    if (value == null) {
      _headers.remove(normalized);
      _originalNames.remove(normalized);
      _flattenedHeaderValueCount -= previousLength;
      _updateComputedFields(normalized);
      return;
    }
    _headers[normalized] = <String>[value];
    _flattenedHeaderValueCount += 1 - previousLength;
    _originalNames[normalized] = normalized;
    _updateComputedFields(normalized);
  }

  @pragma('vm:prefer-inline')
  void _updateHostHeader() {
    final hostValue = _host;
    if (hostValue == null || hostValue.isEmpty) {
      _setSingleValue(HttpHeaders.hostHeader, null);
      return;
    }
    _setSingleValue(
      HttpHeaders.hostHeader,
      _port == null ? hostValue : '$hostValue:${_port!}',
    );
  }

  /// Refreshes typed header cache fields after [key] changes.
  void _updateComputedFields(String key) {
    final values = _headers[key];
    switch (key) {
      case HttpHeaders.contentLengthHeader:
        _contentLength = values == null || values.isEmpty
            ? -1
            : int.tryParse(values.last.trim()) ?? -1;
        return;
      case HttpHeaders.contentTypeHeader:
        if (values == null || values.isEmpty) {
          _contentType = null;
          return;
        }
        try {
          _contentType = ContentType.parse(values.last);
        } catch (_) {
          _contentType = null;
        }
        return;
      case HttpHeaders.hostHeader:
        if (values == null || values.isEmpty) {
          _host = null;
          _port = null;
          return;
        }
        final hostValue = values.last;
        final colonIndex = hostValue.lastIndexOf(':');
        if (colonIndex != -1 &&
            colonIndex < hostValue.length - 1 &&
            int.tryParse(hostValue.substring(colonIndex + 1)) != null) {
          _host = hostValue.substring(0, colonIndex);
          _port = int.tryParse(hostValue.substring(colonIndex + 1));
          return;
        }
        _host = hostValue;
        _port = null;
        return;
      case HttpHeaders.dateHeader:
        _date = _parseHttpDate(values);
        return;
      case HttpHeaders.expiresHeader:
        _expires = _parseHttpDate(values);
        return;
      case HttpHeaders.ifModifiedSinceHeader:
        _ifModifiedSince = _parseHttpDate(values);
        return;
      case HttpHeaders.transferEncodingHeader:
        if (values == null) {
          _chunkedTransferEncoding = false;
          return;
        }
        _chunkedTransferEncoding = _containsTokenIgnoreCase(values, 'chunked');
        return;
      case HttpHeaders.connectionHeader:
        if (values == null || values.isEmpty) {
          _persistentConnection = true;
          return;
        }
        if (_containsTokenIgnoreCase(values, 'close')) {
          _persistentConnection = false;
          return;
        }
        if (_containsTokenIgnoreCase(values, 'keep-alive')) {
          _persistentConnection = true;
        }
        return;
    }
  }

  bool _containsTokenIgnoreCase(List<String> values, String token) {
    for (var i = 0; i < values.length; i++) {
      if (_equalsAsciiIgnoreCase(values[i], token)) {
        return true;
      }
    }
    return false;
  }

  DateTime? _parseHttpDate(List<String>? values) {
    if (values == null || values.isEmpty) {
      return null;
    }
    try {
      return HttpDate.parse(values.last);
    } catch (_) {
      return null;
    }
  }
}
