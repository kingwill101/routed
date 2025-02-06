import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:8080';

  // Test simple query parameters
  print('\nTesting simple query parameters:');
  var response = await http.get(
    Uri.parse('$baseUrl/search?q=dart&page=2&sort=desc'),
  );
  print('Search with query parameters:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test array query parameters
  print('\nTesting array query parameters:');
  response = await http.get(
    Uri.parse(
        '$baseUrl/filter?tag=web&tag=api&category=tutorial&category=guide'),
  );
  print('Filter with array parameters:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test query parameter validation (success)
  print('\nTesting query parameter validation (success):');
  response = await http.get(
    Uri.parse('$baseUrl/products?minPrice=10&maxPrice=100&category=books'),
  );
  print('Products with valid parameters:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');

  // Test query parameter validation (failure)
  print('\nTesting query parameter validation (failure):');
  response = await http.get(
    Uri.parse('$baseUrl/products?minPrice=invalid&maxPrice=100'),
  );
  print('Products with invalid parameters:');
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
