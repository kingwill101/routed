import 'package:server_native/server_native.dart';
import 'package:test/test.dart';

void main() {
  test('exports server boot APIs from package root', () {
    expect(FfiMultiServer, isNotNull);
    expect(NativeHttpServer, isNotNull);
    expect(FfiServerBind, isNotNull);
    expect(serveFfi, isNotNull);
    expect(serveFfiMulti, isNotNull);
    expect(serveSecureFfi, isNotNull);
    expect(serveSecureFfiMulti, isNotNull);
    expect(serveFfiHttp, isNotNull);
    expect(serveSecureFfiHttp, isNotNull);
  });
}
