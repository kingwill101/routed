import 'package:routed/routed.dart';
import 'package:routed_class_view/routed_class_view.dart';
import 'package:routed_testing/routed_testing.dart';

class RequestInfoTestView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    final params = await getParams();
    final queryParams = await getQueryParams();
    final routeParams = await getRouteParams();
    final headers = await getHeaders();
    final body = {
      'adapter_info': {
        'method': await adapter.getMethod(),
        'uri': (await adapter.getUri()).toString(),
        'params': params,
        'query_params': queryParams,
        'route_params': routeParams,
        'headers': headers,
        'specific_param': await getParam('id'),
        'specific_header': await getHeader('authorization'),
      },
    };
    await sendJson(body);
  }
}

void main() {
  late final engine = Engine()
    ..getView('/request-info', () => RequestInfoTestView())
    ..getView('/request-info/{id}', () => RequestInfoTestView());

  // engineTest('should extract HTTP method correctly', (eng, client) async {
  //   final response = await client.get('/request-info');
  //   response.assertStatus(200).assertJson((json) {
  //     json.where('adapter_info.method', 'GET');
  //   });
  // }, engine: engine, transportMode: TransportMode.ephemeralServer);
  //
  // engineTest('should extract URI correctly', (eng, client) async {
  //   final response = await client.get('/request-info?search=dart&page=2');
  //   response.assertStatus(200).assertJson((json) {
  //     json.has('adapter_info.uri');
  //   });
  // }, engine: engine);

  engineTest('should extract route parameters correctly', (eng, client) async {
    final response = await client.get('/request-info/user123');
    response.assertStatus(200).assertJson((json) {
      json
          .where('adapter_info.specific_param', 'user123')
          .where('adapter_info.route_params.id', 'user123');
    });
  }, engine: engine);

  // engineTest('should extract query parameters correctly', (eng, client) async {
  //   final response = await client.get('/request-info?filter=active&sort=date');
  //   response.assertStatus(200).assertJson((json) {
  //     json
  //         .where('adapter_info.query_params.filter', 'active')
  //         .where('adapter_info.query_params.sort', 'date');
  //   });
  // }, engine: engine);
  //
  // engineTest('should combine route and query parameters', (eng, client) async {
  //   final response =
  //       await client.get('/request-info/user123?search=test&limit=10');
  //   response.assertStatus(200).assertJson((json) {
  //     json
  //         .where('adapter_info.params.id', 'user123')
  //         .where('adapter_info.params.search', 'test')
  //         .where('adapter_info.params.limit', '10');
  //   });
  // }, engine: engine);
  //
  // engineTest('should extract headers correctly', (eng, client) async {
  //   final response = await client.get('/request-info', headers: {
  //     'Authorization': ['Bearer token123'],
  //     'Content-Type': ['application/json'],
  //   });
  //
  //   response.assertStatus(200).assertJson((json) {
  //     json
  //         .where('adapter_info.specific_header', 'Bearer token123')
  //         .where('adapter_info.headers.authorization', 'Bearer token123');
  //   });
  // }, engine: engine);
}
