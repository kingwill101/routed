import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Wraps an [HttpRequest] to enforce a maximum request body size limit.
///
/// This class intercepts the request stream and tracks the total bytes read.
/// If the limit is exceeded, an [HttpException] is thrown and the stream is
/// closed, preventing excessive memory consumption from large requests.
///
/// Example:
/// ```dart
/// final maxSize = 5 * 1024 * 1024; // 5MB
/// final wrapped = WrappedRequest(request, maxSize);
/// ```
class WrappedRequest implements HttpRequest {
  /// The original HTTP request being wrapped.
  final HttpRequest _originalRequest;

  /// Maximum allowed size for the request body in bytes.
  final int _maxRequestSize;

  /// Total number of bytes read so far from the request stream.
  int _totalBytesRead = 0;

  /// Whether the request body size limit has been exceeded.
  bool _limitExceeded = false;

  /// Stream controller for the size-limited request stream.
  final StreamController<List<int>> _limitedStreamController =
      StreamController<List<int>>();

  /// Subscription to the original request stream.
  StreamSubscription<List<int>>? _originalSubscription;

  /// Creates a new wrapped request with a size limit.
  ///
  /// The [_originalRequest] is the HTTP request to wrap, and [_maxRequestSize]
  /// is the maximum number of bytes allowed in the request body.
  ///
  /// If the request body exceeds this limit, an [HttpException] is thrown
  /// with the message "Request body exceeds the maximum allowed size."
  WrappedRequest(this._originalRequest, this._maxRequestSize) {
    _originalSubscription = _originalRequest.listen(
      (List<int> chunk) {
        _totalBytesRead += chunk.length;
        if (_totalBytesRead > _maxRequestSize) {
          if (!_limitExceeded) {
            _limitExceeded = true;
            _limitedStreamController.addError(
              const HttpException(
                'Request body exceeds the maximum allowed size.',
              ),
            );
            _limitedStreamController.close();
            // Stop listening to the original subscription
            _originalSubscription?.cancel();
            // Still consume remaining chunks to prevent connection issues
            _originalRequest.drain<void>();
          }
          // Don't add the chunk to the limited stream after the limit has been exceeded
        } else {
          _limitedStreamController.add(chunk);
        }
      },
      onError: (Object error) {
        if (!_limitedStreamController.isClosed) {
          _limitedStreamController.addError(error);
          _limitedStreamController.close();
        }
      },
      onDone: () {
        if (!_limitedStreamController.isClosed) {
          _limitedStreamController.close();
        }
      },
      cancelOnError: true,
    );
  }

  @override
  HttpConnectionInfo? get connectionInfo => _originalRequest.connectionInfo;

  @override
  int get contentLength => _originalRequest.contentLength;

  @override
  List<Cookie> get cookies => _originalRequest.cookies;

  @override
  HttpHeaders get headers => _originalRequest.headers;

  @override
  String get method => _originalRequest.method;

  @override
  Uri get uri => _originalRequest.uri;

  @override
  String get protocolVersion => _originalRequest.protocolVersion;

  @override
  HttpResponse get response => _originalRequest.response;

  @override
  HttpSession get session => _originalRequest.session;

  @override
  bool get persistentConnection => _originalRequest.persistentConnection;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _limitedStreamController.stream.cast<Uint8List>().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<bool> any(bool Function(Uint8List element) test) async {
    return _limitedStreamController.stream.cast<Uint8List>().any(test);
  }

  @override
  Stream<Uint8List> asBroadcastStream({
    void Function(StreamSubscription<Uint8List> subscription)? onListen,
    void Function(StreamSubscription<Uint8List> subscription)? onCancel,
  }) {
    return _limitedStreamController.stream.cast<Uint8List>().asBroadcastStream(
      onListen: onListen,
      onCancel: onCancel,
    );
  }

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(Uint8List event) convert) {
    return _limitedStreamController.stream.cast<Uint8List>().asyncExpand(
      convert,
    );
  }

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(Uint8List event) convert) {
    return _limitedStreamController.stream.cast<Uint8List>().asyncMap(convert);
  }

  @override
  Stream<R> cast<R>() {
    return _limitedStreamController.stream.cast();
  }

  @override
  Future<bool> contains(Object? needle) async {
    return _limitedStreamController.stream.contains(needle);
  }

  @override
  Stream<Uint8List> distinct([
    bool Function(Uint8List previous, Uint8List next)? equals,
  ]) {
    return _limitedStreamController.stream.cast<Uint8List>().distinct(equals);
  }

  @override
  Future<Uint8List> elementAt(int index) async {
    return _limitedStreamController.stream.cast<Uint8List>().elementAt(index);
  }

  @override
  Future<bool> every(bool Function(Uint8List element) test) async {
    return _limitedStreamController.stream.cast<Uint8List>().every(test);
  }

  @override
  Stream<S> expand<S>(Iterable<S> Function(Uint8List element) convert) {
    return _limitedStreamController.stream.cast<Uint8List>().expand(convert);
  }

  @override
  Future<Uint8List> get first async {
    return _limitedStreamController.stream.cast<Uint8List>().first;
  }

  @override
  Future<Uint8List> firstWhere(
    bool Function(Uint8List element) test, {
    Uint8List Function()? orElse,
  }) async {
    return _limitedStreamController.stream.cast<Uint8List>().firstWhere(
      test,
      orElse: orElse,
    );
  }

  @override
  Future<S> fold<S>(
    S initialValue,
    S Function(S previous, Uint8List element) combine,
  ) async {
    return _limitedStreamController.stream.cast<Uint8List>().fold(
      initialValue,
      combine,
    );
  }

  @override
  Future<void> forEach(void Function(Uint8List element) action) async {
    return _limitedStreamController.stream.cast<Uint8List>().forEach(action);
  }

  @override
  Stream<Uint8List> handleError(
    Function onError, {
    bool Function(dynamic error)? test,
  }) {
    return _limitedStreamController.stream.cast<Uint8List>().handleError(
      onError,
      test: test,
    );
  }

  @override
  bool get isBroadcast => _limitedStreamController.stream.isBroadcast;

  @override
  Future<bool> get isEmpty async {
    return _limitedStreamController.stream.isEmpty;
  }

  @override
  Future<String> join([String separator = ""]) async {
    return _limitedStreamController.stream.join(separator);
  }

  @override
  Future<Uint8List> get last async {
    return _limitedStreamController.stream.cast<Uint8List>().last;
  }

  @override
  Future<Uint8List> lastWhere(
    bool Function(Uint8List element) test, {
    Uint8List Function()? orElse,
  }) async {
    return _limitedStreamController.stream.cast<Uint8List>().lastWhere(
      test,
      orElse: orElse,
    );
  }

  @override
  Future<int> get length async {
    return _limitedStreamController.stream.length;
  }

  @override
  Stream<S> map<S>(S Function(Uint8List event) convert) {
    return _limitedStreamController.stream.cast<Uint8List>().map(convert);
  }

  @override
  Future<void> pipe(StreamConsumer<List<int>> streamConsumer) async {
    return _limitedStreamController.stream.pipe(streamConsumer);
  }

  @override
  Future<Uint8List> reduce(
    Uint8List Function(Uint8List previous, Uint8List element) combine,
  ) async {
    return _limitedStreamController.stream.cast<Uint8List>().reduce(combine);
  }

  @override
  Uri get requestedUri => _originalRequest.requestedUri;

  @override
  Future<Uint8List> get single async {
    return _limitedStreamController.stream.cast<Uint8List>().single;
  }

  @override
  Future<Uint8List> singleWhere(
    bool Function(Uint8List element) test, {
    Uint8List Function()? orElse,
  }) async {
    return _limitedStreamController.stream.cast<Uint8List>().singleWhere(
      test,
      orElse: orElse,
    );
  }

  @override
  Stream<Uint8List> skip(int count) {
    return _limitedStreamController.stream.cast<Uint8List>().skip(count);
  }

  @override
  Stream<Uint8List> skipWhile(bool Function(Uint8List element) test) {
    return _limitedStreamController.stream.cast<Uint8List>().skipWhile(test);
  }

  @override
  Stream<Uint8List> take(int count) {
    return _limitedStreamController.stream.cast<Uint8List>().take(count);
  }

  @override
  Stream<Uint8List> takeWhile(bool Function(Uint8List element) test) {
    return _limitedStreamController.stream.cast<Uint8List>().takeWhile(test);
  }

  @override
  Stream<Uint8List> timeout(
    Duration timeLimit, {
    void Function(EventSink<Uint8List> sink)? onTimeout,
  }) {
    return _limitedStreamController.stream.cast<Uint8List>().timeout(
      timeLimit,
      onTimeout: onTimeout,
    );
  }

  @override
  Future<List<Uint8List>> toList() async {
    return _limitedStreamController.stream.cast<Uint8List>().toList();
  }

  @override
  Future<Set<Uint8List>> toSet() async {
    return _limitedStreamController.stream.cast<Uint8List>().toSet();
  }

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) {
    return _limitedStreamController.stream.transform(streamTransformer);
  }

  @override
  Stream<Uint8List> where(bool Function(Uint8List event) test) {
    return _limitedStreamController.stream.cast<Uint8List>().where(test);
  }

  @override
  Future<E> drain<E>([E? futureValue]) async {
    return _limitedStreamController.stream.drain(futureValue);
  }

  @override
  X509Certificate? get certificate => _originalRequest.certificate;
}
