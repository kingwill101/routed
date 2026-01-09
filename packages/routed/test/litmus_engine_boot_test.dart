import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'test_engine.dart';

Future<void> main() async {
  final engine = testEngine()
    ..get("/hello", (c) => c.string("world")).name("hello")
    ..get("/world", (c) => c.string("hello"));

  engineTest('GET /world returns hello', (eng, client) async {
    final response = await client.get('/world');
    response.assertStatus(200).assertBodyContains("hello");
  }, engine: engine);

  engineTest('GET /hello returns world', (eng, client) async {
    final response = await client.get('/hello');
    response.assertStatus(200).assertBodyContains("world");
  }, engine: engine);
}
