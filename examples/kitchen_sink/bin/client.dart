import 'dart:convert';

import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';
  final client = http.Client();

  try {
    // Test GET /recipes
    print('\nTesting GET /recipes:');
    var response = await client.get(Uri.parse('$baseUrl/recipes'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Test POST /recipes
    print('\nTesting POST /recipes:');
    response = await http.post(
      Uri.parse('$baseUrl/recipes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'New Recipe',
        'ingredients': ['Ingredient 1', 'Ingredient 2'],
        'instructions': 'Do something',
        'prepTime': 10,
        'cookTime': 20,
        'category': 'dinner'
      }),
    );
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Test GET /recipes/{id}
    print('\nTesting GET /recipes/1:');
    response = await client.get(Uri.parse('$baseUrl/recipes/1'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Test PUT /recipes/{id}
    print('\nTesting PUT /recipes/1:');
    response = await http.put(
      Uri.parse('$baseUrl/recipes/1'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'Updated Recipe',
        'ingredients': ['New Ingredient 1', 'New Ingredient 2'],
        'instructions': 'Do something else',
        'prepTime': 15,
        'cookTime': 25,
        'category': 'lunch'
      }),
    );
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Test DELETE /recipes/{id}
    print('\nTesting DELETE /recipes/1:');
    response = await client.delete(Uri.parse('$baseUrl/recipes/1'));
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } finally {
    client.close();
  }
}
