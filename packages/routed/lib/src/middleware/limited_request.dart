import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// ignore: unused_element
class _LimitedHttpRequestWrapper implements HttpRequest {
  final HttpRequest _originalRequest;
  final Stream<List<int>> _limitedStream;

  _LimitedHttpRequestWrapper(this._originalRequest, this._limitedStream);

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
  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _limitedStream.cast<Uint8List>().listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  @override
  Stream<Uint8List> asBroadcastStream(
          {void Function(StreamSubscription<Uint8List> subscription)? onListen,
          void Function(StreamSubscription<Uint8List> subscription)?
              onCancel}) =>
      _limitedStream
          .cast<Uint8List>()
          .asBroadcastStream(onListen: onListen, onCancel: onCancel);

  @override
  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(Uint8List event) convert) =>
      _limitedStream.cast<Uint8List>().asyncExpand(convert);

  @override
  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(Uint8List event) convert) =>
      _limitedStream.cast<Uint8List>().asyncMap(convert);

  @override
  Stream<R> cast<R>() => _limitedStream.cast();

  @override
  Future<bool> contains(Object? needle) => _limitedStream.contains(needle);

  @override
  @override
  Stream<Uint8List> distinct(
          [bool Function(Uint8List previous, Uint8List next)? equals]) =>
      _limitedStream.cast<Uint8List>().distinct(equals);

  @override
  @override
  Future<Uint8List> elementAt(int index) =>
      _limitedStream.cast<Uint8List>().elementAt(index);

  @override
  @override
  Future<bool> every(bool Function(Uint8List element) test) =>
      _limitedStream.cast<Uint8List>().every(test);

  @override
  @override
  Stream<S> expand<S>(Iterable<S> Function(Uint8List element) convert) =>
      _limitedStream.cast<Uint8List>().expand(convert);

  @override
  @override
  Future<Uint8List> get first => _limitedStream.cast<Uint8List>().first;

  @override
  @override
  Future<Uint8List> firstWhere(bool Function(Uint8List element) test,
          {Uint8List Function()? orElse}) =>
      _limitedStream.cast<Uint8List>().firstWhere(test, orElse: orElse);

  @override
  @override
  Future<S> fold<S>(
          S initialValue, S Function(S previous, Uint8List element) combine) =>
      _limitedStream.cast<Uint8List>().fold(initialValue, combine);

  @override
  @override
  Future<void> forEach(void Function(Uint8List element) action) =>
      _limitedStream.cast<Uint8List>().forEach(action);

  @override
  @override
  Stream<Uint8List> handleError(Function onError,
          {bool Function(dynamic error)? test}) =>
      _limitedStream.cast<Uint8List>().handleError(onError, test: test);

  @override
  bool get isBroadcast => _limitedStream.isBroadcast;

  @override
  Future<bool> get isEmpty => _limitedStream.isEmpty;

  @override
  Future<String> join([String separator = ""]) =>
      _limitedStream.join(separator);

  @override
  @override
  Future<Uint8List> get last => _limitedStream.cast<Uint8List>().last;
  @override
  @override
  Future<Uint8List> lastWhere(bool Function(Uint8List element) test,
          {Uint8List Function()? orElse}) =>
      _limitedStream.cast<Uint8List>().lastWhere(test, orElse: orElse);

  @override
  Future<int> get length => _limitedStream.length;

  @override
  @override
  Stream<S> map<S>(S Function(Uint8List event) convert) =>
      _limitedStream.cast<Uint8List>().map(convert);

  @override
  Future<void> pipe(StreamConsumer<List<int>> streamConsumer) =>
      _limitedStream.pipe(streamConsumer);

  @override
  @override
  Future<Uint8List> reduce(
          Uint8List Function(Uint8List previous, Uint8List element) combine) =>
      _limitedStream.cast<Uint8List>().reduce(combine);

  @override
  Uri get requestedUri => _originalRequest.requestedUri;

  @override
  @override
  Future<Uint8List> get single => _limitedStream.cast<Uint8List>().single;
  @override
  @override
  Future<Uint8List> singleWhere(bool Function(Uint8List element) test,
          {Uint8List Function()? orElse}) =>
      _limitedStream.cast<Uint8List>().singleWhere(test, orElse: orElse);

  @override
  @override
  Stream<Uint8List> skip(int count) =>
      _limitedStream.cast<Uint8List>().skip(count);

  @override
  @override
  Stream<Uint8List> skipWhile(bool Function(Uint8List element) test) =>
      _limitedStream.cast<Uint8List>().skipWhile(test);

  @override
  @override
  Stream<Uint8List> take(int count) =>
      _limitedStream.cast<Uint8List>().take(count);

  @override
  @override
  Stream<Uint8List> takeWhile(bool Function(Uint8List element) test) =>
      _limitedStream.cast<Uint8List>().takeWhile(test);

  @override
  @override
  Stream<Uint8List> timeout(Duration timeLimit,
          {void Function(EventSink<Uint8List> sink)? onTimeout}) =>
      _limitedStream.cast<Uint8List>().timeout(timeLimit, onTimeout: onTimeout);

  @override
  @override
  Future<List<Uint8List>> toList() => _limitedStream.cast<Uint8List>().toList();

  @override
  @override
  Future<Set<Uint8List>> toSet() => _limitedStream.cast<Uint8List>().toSet();

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) =>
      _limitedStream.transform(streamTransformer);

  @override
  @override
  Stream<Uint8List> where(bool Function(Uint8List event) test) =>
      _limitedStream.cast<Uint8List>().where(test);

  @override
  Future<E> drain<E>([E? futureValue]) => _limitedStream.drain(futureValue);

  @override
  X509Certificate? get certificate => _originalRequest.certificate;

  @override
  Future<bool> any(bool Function(Uint8List element) test) {
    return _limitedStream.any((d) => test(Uint8List.fromList(d)));
  }
}
