import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'assertable_json/assertable_json.dart';
import 'assertable_json/assertable_json_base.dart';

/// A class representing a test response, including status code, headers, body, and URI.
class TestResponse {
  /// The HTTP status code of the response.
  final int statusCode;

  /// The headers of the response as a map where the key is the header name and the value is a list of header values.
  final Map<String, List<String>> headers;

  /// The body of the response as a string.
  final String body;

  /// The parsed JSON body of the response, if applicable.
  dynamic jsonBody;

  /// The URI of the request that generated this response.
  final String uri;

  /// Constructs a [TestResponse] with the given status code, headers, body, and URI.
  TestResponse(
      {required this.statusCode,
      required this.headers,
      required this.body,
      required this.uri}) {
    _parseJsonIfApplicable();
  }

  /// Parses the body as JSON if the content type header indicates that the body is JSON.
  void _parseJsonIfApplicable() {
    if (!_headerExists(HttpHeaders.contentTypeHeader)) return;
    final ct = _headerEntry(HttpHeaders.contentTypeHeader) ?? '';
    if (ct[0].contains('application/json')) {
      try {
        jsonBody = jsonDecode(body);
      } catch (_) {
        // ignore or handle error
      }
    }
  }

  /// Asserts that the status code of the response matches the expected status code.
  ///
  /// Throws a [TestFailure] if the status codes do not match.
  TestResponse assertStatus(int expected) {
    if (statusCode != expected) {
      throw TestFailure('Expected status $expected, but got $statusCode');
    }
    return this;
  }

  /// Retrieves the JSON body or a specific path within the JSON body.
  ///
  /// If [path] is provided, it retrieves the value at that path.
  /// Throws a [TestFailure] if the JSON body is not present or the path does not exist.
  dynamic json([String? path]) {
    if (jsonBody == null) {
      throw TestFailure('No JSON body to assert against.');
    }
    if (path == null) {
      return jsonBody;
    }
    final parts = path.split('.');
    dynamic current = jsonBody;
    for (final part in parts) {
      if (current is! Map<String, dynamic>) {
        throw TestFailure('Path "$path" does not exist in JSON body.');
      }
      current = current[part];
    }
    return current;
  }

  /// Retrieves the value of a header by its key.
  ///
  /// Throws a [TestFailure] if the header is not present.
  dynamic _headerEntry(String key) => headers.entries
      .firstWhere((entry) => entry.key.toLowerCase() == key.toLowerCase())
      .value;

  /// Retrieves the value of a header by its key.
  ///
  /// Throws a [TestFailure] if the header is not present.
  dynamic header(String key) {
    assertHasHeader(key);
    return _headerEntry(key);
  }

  /// Checks if a header exists by its key.
  bool _headerExists(String key) =>
      headers.keys.any((k) => k.toLowerCase() == key.toLowerCase());

  /// Asserts that a header is present by its key.
  ///
  /// Throws a [TestFailure] if the header is not present.
  TestResponse assertHasHeader(String key) {
    if (!_headerExists(key)) {
      throw TestFailure(
          'Expected header "$key" to be present, but it was not.');
    }
    return this;
  }

  /// Asserts that the header identified by [key] contains the specified [value].
  ///
  /// If the header is a string or a list, it checks if the header contains the [value].
  /// Throws a [TestFailure] if the header does not contain the [value] or if the header
  /// is not a string or list.
  TestResponse assertHeaderContains(String key, dynamic value) {
    assertHasHeader(key);
    final actual = headers.entries
        .firstWhere((entry) => entry.key.toLowerCase() == key.toLowerCase())
        .value;

    if (value is String) {
      if (actual.isEmpty || !actual.contains(value)) {
        throw TestFailure(
            'Expected header "$key" to contain "$value", but got "$actual"');
      }
      return this;
    } else if (value is Iterable) {
      for (var v in value) {
        if (actual.isEmpty || !actual[0].contains(v)) {
          throw TestFailure(
              'Expected header "$key($actual)" to contain "$v", but never found it');
        }
      }
      return this;
    }

    throw TestFailure(
        'Expected header "$key" to be a string or list, but got "$actual"');
  }

  /// Asserts that the header identified by [key] matches the specified [value].
  ///
  /// Throws a [TestFailure] if the header does not match the [value].
  TestResponse assertHeader(String key, String value) {
    assertHasHeader(key);
    final actual = headers.entries
        .firstWhere((entry) => entry.key.toLowerCase() == key.toLowerCase())
        .value;
    if (actual.isEmpty || actual.first != value) {
      throw TestFailure(
          'Expected header "$key" to be "$value", but got "$actual"');
    }
    return this;
  }

  /// Asserts that the body contains the specified [substring].
  ///
  /// Throws a [TestFailure] if the body does not contain the [substring].
  TestResponse assertBodyContains(String substring) {
    if (!body.contains(substring)) {
      throw TestFailure(
          'Expected body to contain "$substring", but it did not.\nwanted: $substring\ngot: $body');
    }
    return this;
  }

  /// Asserts that the body matches the specified [expectedBody].
  ///
  /// Throws a [TestFailure] if the body does not match the [expectedBody].
  TestResponse assertBodyEquals(String expectedBody) {
    if (body != expectedBody) {
      throw TestFailure(
          'Expected body to be "$expectedBody", but got "$body".');
    }
    return this;
  }

  /// Asserts that the body is not empty.
  ///
  /// Throws a [TestFailure] if the body is empty.
  TestResponse assertBodyIsNotEmpty() {
    if (body.isEmpty) {
      throw TestFailure('Expected body to not be empty, but it was.');
    }
    return this;
  }

  /// Asserts that the value at the specified JSON [path] matches the [expected] value.
  ///
  /// Throws a [TestFailure] if the value does not match the [expected] value.
  TestResponse assertJsonPath(String path, dynamic expected) {
    final actual = json(path);
    if (actual != expected) {
      throw TestFailure(
          'Expected JSON path "$path" to be "$expected", but got "$actual".');
    }
    return this;
  }

  /// Asserts that the JSON body matches the expectations defined in the [callback].
  ///
  /// The [callback] is a function that takes an [AssertableJson] object and performs assertions on it.
  TestResponse assertJson(AssertableJsonCallback callback) {
    callback(AssertableJson(json()));
    return this;
  }

  /// Asserts that the JSON body contains the specified [partial] map.
  ///
  /// Throws a [TestFailure] if the JSON body does not contain the [partial] map.
  TestResponse assertJsonContains(Map<String, dynamic> partial) {
    if (jsonBody == null || jsonBody is! Map<String, dynamic>) {
      throw TestFailure('No JSON map body to check.');
    }
    final jsonMap = jsonBody as Map<String, dynamic>;
    partial.forEach((key, value) {
      if (!jsonMap.containsKey(key)) {
        throw TestFailure(
            'Expected JSON key "$key" not found. \nexpected: "$value"\nActual: "${jsonMap[key]}"');
      }

      if (value is List && jsonMap[key] is List) {
        final list = jsonMap[key] as List<dynamic>;
        final listValues = list.map((e) => e.toString()).toList();
        final expectedValues = value.map((e) => e.toString()).toList();
        if (listValues.toSet().difference(expectedValues.toSet()).isNotEmpty) {
          throw TestFailure(
              'Expected JSON list "$key" to contain "$value", but got "${jsonMap[key]}"');
        }
      } else if (value is Map && jsonMap[key] is Map) {
        // Convert both maps to string representation for comparison
        final actualStr = jsonEncode(jsonMap[key]);
        final expectedStr = jsonEncode(value);
        if (actualStr != expectedStr) {
          throw TestFailure(
              'Expected JSON key "$key" with value "$value", but got \n"${jsonMap[key]}"');
        }
      } else if (jsonMap[key] != value) {
        throw TestFailure(
            'Expected JSON key "$key" with value "$value", but got "${jsonMap[key]}"');
      }
    });
    return this;
  }

  /// Custom assertion to check if JSON contains specific file data.
  ///
  /// Asserts that the JSON body contains a list of files under the specified [key] and that one of the files has the specified [filename].
  /// Throws a [TestFailure] if the JSON body does not contain the [key] or if the list does not contain a file with the [filename].
  TestResponse assertJsonFilesContain(String key, String filename) {
    if (jsonBody == null || jsonBody is! Map<String, dynamic>) {
      throw TestFailure('No JSON map body to check for files.');
    }
    final jsonMap = jsonBody as Map<String, dynamic>;
    if (!jsonMap.containsKey(key)) {
      throw TestFailure('JSON does not contain key "$key".');
    }
    final files = jsonMap[key];
    if (files is! List) {
      throw TestFailure('Expected "$key" to be a List.');
    }
    final containsFile = files.any(
        (file) => file is Map<String, dynamic> && file['filename'] == filename);
    if (!containsFile) {
      throw TestFailure(
          'Expected JSON to contain file "$filename" under "$key".');
    }
    return this;
  }

  /// Dumps the response in an HTTP-like format, including status code, headers, and body.
  ///
  /// This method prints the URI, status line, headers, and body of the response.
  void dump() {
    // Print the URI
    print(uri);

    // Print the status line
    print('HTTP/1.1 $statusCode ${_getStatusMessage(statusCode)}');

    // Print the headers
    headers.forEach((key, values) {
      for (final value in values) {
        print('$key: $value');
      }
    });
    print('');

    // Print the body
    print(body);
  }

  /// Helper method to get the status message for a given status code.
  ///
  /// Returns a string representing the status message for the given [statusCode].
  String _getStatusMessage(int statusCode) {
    HttpStatus.ok;
    switch (statusCode) {
      case 200:
        return 'OK';
      case 201:
        return 'Created';
      case 204:
        return 'No Content';
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 422:
        return 'Unprocessable Entity';
      case 429:
        return 'Too Many Requests';
      case 500:
        return 'Internal Server Error';
      default:
        return 'Unknown';
    }
  }
}
