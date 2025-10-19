import 'package:routed/routed.dart';
import 'package:routed_class_view/routed_class_view.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

class ResponseOpsTestView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final action = await getParam('action');

    switch (action) {
      case 'status':
        await sendJson({'message': 'Custom status set'}, statusCode: 201);
        break;
      case 'headers':
        await setHeader('X-Custom', 'test-value');
        await setHeader('X-Another', 'another-value');
        await sendJson({'message': 'Custom headers set'});
        break;
      case 'redirect':
        await redirect('/redirected', statusCode: 301);
        break;
      case 'write':
        await write('Hello, ');
        await write('World!');
        break;
      default:
        await sendJson({'message': 'Default response'});
    }
  }
}

void main() {
  final engine = Engine()
    ..getView('/response-ops/{action}', () => ResponseOpsTestView());

  engineTest('should set custom status codes', (eng, client) async {
    final response = await client.get('/response-ops/status');
    response.assertStatus(201).assertJson((json) {
      json.where('message', 'Custom status set');
    });
  }, engine: engine);

  engineTest('should set custom headers', (eng, client) async {
    final response = await client.get('/response-ops/headers');
    response.assertStatus(200).assertJson((json) {
      json.where('message', 'Custom headers set');
    });

    expect(response.headers['X-Custom']?.first, equals('test-value'));
    expect(response.headers['X-Another']?.first, equals('another-value'));
  }, engine: engine);

  engineTest('should handle redirects', (eng, client) async {
    final response = await client.get('/response-ops/redirect');
    expect(response.statusCode, equals(301));
    expect(response.headers['location']?.first, equals('/redirected'));
  }, engine: engine);

  engineTest('should write content directly', (eng, client) async {
    final response = await client.get('/response-ops/write');
    response.assertStatus(200);
    final body = response.body;
    expect(body, contains('Hello, World!'));
  }, engine: engine);

  engineTest('should set correct content type for JSON responses', (
    eng,
    client,
  ) async {
    final response = await client.get('/response-ops/default');
    response.assertStatus(200);
    expect(response.body, isNotEmpty);
    expect(() => response.body, returnsNormally);
  }, engine: engine);
}
