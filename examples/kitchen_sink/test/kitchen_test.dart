import 'dart:convert';

import 'package:kitchen_sink_example/app.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  engineGroup(
    'Kitchen Sink Tests',
    engine: buildApp(),
    define: (engine, client) {
      test('GET /api/recipes requires API key', () async {
        final response = await client.get('/api/recipes');
        expect(response.statusCode, 401);
        expect(response.body, 'Unauthorized');
      });

      test('GET /api/recipes returns 200 with API key', () async {
        final response = await client.get('/api/recipes', headers: {
          'X-API-Key': ['YOUR_API_KEY']
        });
        expect(response.statusCode, 200);
      });

      test('POST /recipes creates new recipe', () async {
        final response = await client.post('/api/recipes', headers: {
          'X-API-Key': ['YOUR_API_KEY']
        }, {
          'name': 'Test Recipe',
          'ingredients': ['ingredient1'],
          'instructions': 'test instructions',
          'prepTime': 10,
          'cookTime': 20,
          'category': 'dinner'
        });
        response.assertStatus(201);
      });

      test('Recipe endpoints use caching', () async {
        // Create recipe with valid data
        final createResponse = await client.post(
            '/api/recipes',
            headers: {
              'X-API-Key': ['YOUR_API_KEY']
            },
            jsonEncode({
              // Properly encode JSON body
              'name': 'Cache Test Recipe', // At least 3 chars
              'description': 'Test description',
              'ingredients': ['test ingredient'], // Valid array
              'instructions': 'Test instructions',
              'prepTime': 10,
              'cookTime': 20,
              'category': 'dinner' // Valid enum value
            }));
        createResponse.assertStatus(201);

        final recipeData = jsonDecode(createResponse.body);
        final recipeId = recipeData['id']; // Get actual ID from response

        // First request with valid ID
        final firstResponse =
            await client.get('/api/recipes/$recipeId', headers: {
          'X-API-Key': ['YOUR_API_KEY']
        });
        firstResponse.assertStatus(200);

        // Second request to verify cache
        final secondResponse =
            await client.get('/api/recipes/$recipeId', headers: {
          'X-API-Key': ['YOUR_API_KEY']
        });
        secondResponse.assertStatus(200);
        expect(secondResponse.body, equals(firstResponse.body));
      });

      test('Session persistence works', () async {
        await client.get('/set');
        final response = await client.get('/test');
        expect(response.body, contains('it worked!'));
      });

      test('Web routes require session for protected endpoints', () async {
        final response = await client.get('/recipes/123/edit');
        expect(response.statusCode, 401);
      });
    },
  );
}
