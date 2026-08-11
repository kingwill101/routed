import 'dart:convert';
import 'dart:io';

import 'package:routed_testing/routed_testing.dart';

import '../../example/blog_app_example.dart' as blog_example;
import '../../example/class_based_views_example.dart' as class_example;

void main() {
  engineTest(
    'blog example lists posts and accepts creation',
    (engine, client) async {
      final listResponse = await client.get('/api/posts');
      listResponse
          .assertStatus(HttpStatus.ok)
          .assertJson(
            (json) => json.has('posts').countBetween('posts', 1, 100),
          );

      final createResponse = await client.post(
        '/api/posts',
        jsonEncode({'title': 'Generated', 'content': 'Created via test'}),
        headers: {
          HttpHeaders.contentTypeHeader: ['application/json'],
        },
      );

      createResponse
          .assertStatus(HttpStatus.created)
          .assertJson((json) => json.has('id').where('title', 'Generated'));
    },
    engine: blog_example.createBlogApp(),
  );

  engineTest(
    'class-based view example supports creation',
    (engine, client) async {
      final response = await client.get('/store/products');
      response
          .assertStatus(HttpStatus.ok)
          .assertJson(
            (json) => json.has('products').countBetween('products', 1, 100),
          );

      final createResponse = await client.post(
        '/store/products',
        jsonEncode({'name': 'Keyboard', 'price': 129.5}),
        headers: {
          HttpHeaders.contentTypeHeader: ['application/json'],
        },
      );

      createResponse
          .assertStatus(HttpStatus.created)
          .assertJson((json) => json.where('name', 'Keyboard'));
    },
    engine: class_example.createProductApp(),
  );
}
