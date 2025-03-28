import 'package:mockito/mockito.dart';

import '../mock.mocks.dart';

/// Creates a mock [Uri] object with the same properties as the provided [uri].
///
/// This function sets up a mock [Uri] object that mimics the behavior of a real
/// [Uri] by configuring its properties to return the same values as the provided
/// [uri]. The mocked properties include:
///
/// * path
/// * queryParameters
/// * query
/// * scheme
/// * host
/// * port
/// * pathSegments
/// * fragment
/// * hasAbsolutePath
/// * hasAuthority
/// * hasEmptyPath
/// * hasPort
/// * hasQuery
///
/// Returns a [MockUri] instance that can be used for testing.
MockUri setupUri(String url) {
  final uriObj = MockUri();
  Uri uri;

  try {
    uri = Uri.parse(url);

    if (!uri.isAbsolute) {
      uri = Uri.parse('http://server_testing.internal$url');
    }
  } catch (e) {
    // Fallback to a basic URI if parsing fails completely
    uri = Uri.parse('http://server_testing.internal/');
  }

  when(uriObj.path).thenAnswer((c) => uri.path);

  // Handle query parameters safely
  when(uriObj.queryParameters).thenAnswer((c) {
    try {
      return uri.queryParameters;
    } catch (e) {
      // Return empty map if query parameter parsing fails
      return <String, String>{};
    }
  });

  when(uriObj.query).thenAnswer((c) => uri.query);
  when(uriObj.scheme).thenAnswer((c) => uri.scheme);
  when(uriObj.host).thenAnswer((c) => uri.host);
  when(uriObj.port).thenAnswer((c) => uri.port);
  when(uriObj.pathSegments).thenAnswer((c) => uri.pathSegments);
  when(uriObj.fragment).thenAnswer((c) => uri.fragment);
  when(uriObj.hasAbsolutePath).thenAnswer((c) => uri.hasAbsolutePath);
  when(uriObj.isAbsolute).thenAnswer((c) => uri.isAbsolute);
  when(uriObj.hasAuthority).thenAnswer((c) => uri.hasAuthority);
  when(uriObj.hasEmptyPath).thenAnswer((c) => uri.hasEmptyPath);
  when(uriObj.hasPort).thenAnswer((c) => uri.hasPort);
  when(uriObj.hasQuery).thenAnswer((c) => uri.hasQuery);
  return uriObj;
}
