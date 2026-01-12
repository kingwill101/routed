import 'dart:convert';
import 'dart:io';

import 'package:routed/src/response.dart';
import 'package:server_testing/mock.dart';

class RenderHarness {
  RenderHarness({required this.response, required this.body});

  final Response response;
  final List<int> body;

  String bodyAsString() => utf8.decode(body);
}

RenderHarness createRenderHarness() {
  final headers = <String, List<String>>{};
  final body = <int>[];
  final mockResponse = MockHttpResponse();
  final mockHeaders = setupHeaders(headers);
  var statusCode = HttpStatus.ok;

  when(mockResponse.headers).thenAnswer((_) => mockHeaders);
  when(mockResponse.statusCode).thenAnswer((_) => statusCode);
  when(mockResponse.statusCode = any).thenAnswer((invocation) {
    statusCode = invocation.positionalArguments.first as int;
  });

  when(mockResponse.write(any)).thenAnswer((invocation) {
    final data = invocation.positionalArguments.first.toString();
    body.addAll(utf8.encode(data));
  });

  when(mockResponse.add(any)).thenAnswer((invocation) {
    body.addAll(invocation.positionalArguments.first as List<int>);
  });

  when(mockResponse.addStream(any)).thenAnswer((invocation) async {
    final stream = invocation.positionalArguments.first as Stream<List<int>>;
    await for (final chunk in stream) {
      body.addAll(chunk);
    }
  });

  when(mockResponse.close()).thenAnswer((_) async {});

  return RenderHarness(response: Response(mockResponse), body: body);
}
