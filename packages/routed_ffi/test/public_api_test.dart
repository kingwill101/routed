import 'package:routed_ffi/routed_ffi.dart';
import 'package:test/test.dart';

void main() {
  test('exports bridge request/response runtime types from package root', () {
    expect(BridgeHttpRequest, isNotNull);
    expect(BridgeHttpResponse, isNotNull);
    expect(BridgeStreamingHttpResponse, isNotNull);
    expect(BridgeHttpHandler, isNotNull);
    expect(BridgeHttpRuntime, isNotNull);
    expect(BridgeRequestFrame, isNotNull);
    expect(BridgeResponseFrame, isNotNull);
    expect(BridgeTunnelFrame, isNotNull);
    expect(BridgeRuntime, isNotNull);
    expect(RoutedBridgeRuntime, isNotNull);
    expect(BridgeConnectionInfo, isNotNull);
    expect(BridgeSession, isNotNull);
    expect(ParsedAuthority, isNotNull);
    expect(serveFfiHttp, isNotNull);
    expect(serveSecureFfiHttp, isNotNull);
  });
}
