import 'package:server_native/server_native.dart';
import 'package:test/test.dart';

void main() {
  test('exports server boot APIs from package root', () {
    expect(NativeMultiServer, isNotNull);
    expect(NativeHttpServer, isNotNull);
    expect(NativeServerBind, isNotNull);
    expect(serveNative, isNotNull);
    expect(serveNativeMulti, isNotNull);
    expect(serveSecureNative, isNotNull);
    expect(serveSecureNativeMulti, isNotNull);
    expect(serveNativeHttp, isNotNull);
    expect(serveSecureNativeHttp, isNotNull);
  });
}
