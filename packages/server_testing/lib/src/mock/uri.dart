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

  final uri = Uri.parse(url);
  if (uri.path != url) {
    when(uriObj.path).thenAnswer((c) {
      return url;
    });
  } else {
    when(uriObj.path).thenAnswer((c) {
      return uri.path;
    });
  }

  when(uriObj.path).thenAnswer((c) => uri.path);
  when(uriObj.queryParameters).thenAnswer((c) => uri.queryParameters);
  when(uriObj.query).thenAnswer((c) => uri.query);
  when(uriObj.scheme).thenAnswer((c) => uri.scheme);
  when(uriObj.host).thenAnswer((c) => uri.host);
  when(uriObj.port).thenAnswer((c) => uri.port);
  when(uriObj.pathSegments).thenAnswer((c) => uri.pathSegments);
  when(uriObj.fragment).thenAnswer((c) => uri.fragment);
  when(uriObj.hasAbsolutePath).thenAnswer((c) => uri.hasAbsolutePath);
  when(uriObj.hasAuthority).thenAnswer((c) => uri.hasAuthority);
  when(uriObj.hasEmptyPath).thenAnswer((c) => uri.hasEmptyPath);
  when(uriObj.hasPort).thenAnswer((c) => uri.hasPort);
  when(uriObj.hasQuery).thenAnswer((c) => uri.hasQuery);
  return uriObj;
}
