import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test/test_engine.dart';

const _providerId = 'keycloak';
const _realm = 'routed-saml';
const _spEntityId = 'https://sp.routed.test/entity';
const _acsPath = '/auth/sso/saml/acs/$_providerId';
const _acsUrl = 'https://sp.routed.test$_acsPath';
const _sessionCookieName = 'saml_keycloak_session';
const _interopUserId = 'saml-keycloak-user';

Future<void> main(List<String> arguments) async {
  final keycloakBaseUrl = _option(arguments, '--keycloak-base-url');
  if (keycloakBaseUrl == null) {
    stderr.writeln(
      'Usage: dart run tool/saml_keycloak_interop.dart '
      '--keycloak-base-url https://127.0.0.1:<port>',
    );
    exitCode = 64;
    return;
  }

  final baseUri = Uri.parse(keycloakBaseUrl);
  if (baseUri.scheme != 'https' || baseUri.host.isEmpty) {
    throw ArgumentError.value(
      keycloakBaseUrl,
      '--keycloak-base-url',
      'must be an absolute HTTPS URL',
    );
  }

  final idp = _Browser();
  Engine? engine;
  TestClient? routed;
  try {
    final idpEntityId = baseUri.resolve('/realms/$_realm').toString();
    final idpSsoUrl = baseUri.resolve('/realms/$_realm/protocol/saml');
    final descriptorUrl = baseUri.resolve(
      '/realms/$_realm/protocol/saml/descriptor',
    );
    final descriptor = await _waitForKeycloak(idp, descriptorUrl);
    final signingCertificate = _firstSigningCertificate(descriptor.body);

    final connection = AuthSamlConnection(
      providerId: _providerId,
      idpEntityId: idpEntityId,
      idpSsoUrl: idpSsoUrl,
      idpSigningCertificate: signingCertificate,
      spEntityId: _spEntityId,
      assertionConsumerServiceUrl: Uri.parse(_acsUrl),
    );
    final store = InMemoryAuthStore();
    final user = await store.users.create(
      AuthUser(id: _interopUserId, email: 'application-owned@example.test'),
    );
    final identityResolver = _IdentityResolver(user);
    final plugin = AuthSamlPlugin<EngineContext>(
      connections: _Catalog(connection),
      replayStore: InMemoryAuthSamlReplayStore(),
      assertionVerifier: AuthPortableSamlXmlDsigVerifier(),
      identityResolver: identityResolver,
      browserBindingResolver: (context) => context.sessionId,
      options: const AuthSamlOptions(allowInMemoryStoreForTesting: true),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        providers: const [],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        plugins: [plugin],
        enforceCsrf: false,
      ),
    );
    final key = base64.encode(List<int>.generate(32, (index) => index + 11));
    engine = testEngine(
      config: EngineConfig(
        security: const EngineSecurityFeatures(csrfProtection: false),
      ),
      providers: [
        RoutedSessionsProvider(
          SessionConfig.cookie(
            appKey: 'base64:$key',
            cookieName: _sessionCookieName,
            options: SessionOptions(
              secure: false,
              httpOnly: true,
              sameSite: SameSite.lax,
            ),
          ),
        ),
      ],
    );
    engine.addGlobalMiddleware(sessionMiddleware());
    engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    routed = TestClient(RoutedRequestHandler(engine));

    final metadata = await routed.get('/auth/sso/saml/metadata/$_providerId');
    _require(metadata.statusCode == HttpStatus.ok, 'SP metadata failed');
    _require(metadata.body.contains(_spEntityId), 'SP entity ID is missing');
    _require(metadata.body.contains(_acsUrl), 'SP ACS URL is missing');

    final started = await routed.postJson('/auth/sso/saml/sign-in', {
      'providerId': _providerId,
      'callbackUrl': '/dashboard',
    });
    _require(started.statusCode == HttpStatus.ok, 'SAML sign-in failed');
    final startedJson = _jsonMap(started.json());
    _require(
      startedJson['destination'] == idpSsoUrl.toString(),
      'SAML destination does not match the selected IdP',
    );
    final fields = _stringMap(startedJson['fields']);
    final relayState = fields['RelayState'];
    _require(relayState != null && relayState.isNotEmpty, 'RelayState missing');
    final initialCookie = started.cookie(_sessionCookieName);
    _require(initialCookie != null, 'Routed session cookie missing');

    final loginPage = await idp.postForm(idpSsoUrl, fields);
    _require(loginPage.statusCode == HttpStatus.ok, 'IdP login page failed');
    final loginForm = _formContaining(loginPage, 'input[name="username"]');
    final loginFields = Map<String, String>.from(loginForm.fields)
      ..['username'] = 'routed-user'
      ..['password'] = 'routed-password';
    final idpPost = await idp.postForm(loginForm.action, loginFields);
    _require(idpPost.statusCode == HttpStatus.ok, 'IdP authentication failed');

    final responseForm = _formContaining(idpPost, 'input[name="SAMLResponse"]');
    _require(
      responseForm.action.toString() == _acsUrl,
      'IdP POST action did not bind the typed provider ACS path',
    );
    final samlResponse = responseForm.fields['SAMLResponse'];
    final returnedRelayState = responseForm.fields['RelayState'];
    _require(samlResponse != null, 'IdP did not issue a SAMLResponse');
    _require(returnedRelayState == relayState, 'IdP changed RelayState');
    final responseXml = utf8.decode(base64.decode(samlResponse!));
    _require(
      RegExp(r'<(?:[A-Za-z_][\w.-]*:)?Signature\b').hasMatch(responseXml),
      'IdP response is not signed',
    );
    _require(
      responseXml.contains(idpEntityId),
      'IdP response issuer is missing',
    );

    final routedForm = Uri(
      queryParameters: {
        'SAMLResponse': samlResponse,
        'RelayState': returnedRelayState,
      },
    ).query;
    final requestHeaders = {
      HttpHeaders.contentTypeHeader: ['application/x-www-form-urlencoded'],
      HttpHeaders.cookieHeader: [_cookieHeader(initialCookie!)],
    };

    final wrongProvider = await routed.post(
      '/auth/sso/saml/acs/not-keycloak',
      routedForm,
      headers: requestHeaders,
    );
    _require(
      wrongProvider.statusCode == HttpStatus.unauthorized,
      'Wrong typed provider path was not rejected',
    );
    _require(
      _jsonMap(wrongProvider.json())['error'] == 'saml_authentication_failed',
      'Wrong provider rejection was not generic',
    );

    final completed = await routed.post(
      _acsPath,
      routedForm,
      headers: requestHeaders,
    );
    _require(
      completed.statusCode == HttpStatus.found,
      'Routed rejected the IdP-issued signed response: ${completed.body}',
    );
    _require(
      completed.headers['location']?.single == '/dashboard',
      'Routed did not restore the callback',
    );
    final sessionCookie = completed.cookie(_sessionCookieName) ?? initialCookie;
    final session = await routed.getJson(
      '/auth/session',
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
      },
    );
    _require(session.statusCode == HttpStatus.ok, 'Session lookup failed');
    final sessionJson = _jsonMap(session.json());
    final sessionUser = _jsonMap(sessionJson['user']);
    _require(
      sessionUser['id'] == _interopUserId,
      'SAML authentication did not issue the application-owned session',
    );
    _require(
      identityResolver.identity?.providerId == _providerId &&
          identityResolver.identity?.idpEntityId == idpEntityId,
      'Identity resolution was not bound to the selected provider and issuer',
    );

    final replay = await routed.post(
      _acsPath,
      routedForm,
      headers: {
        ...requestHeaders,
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
      },
    );
    _require(
      replay.statusCode == HttpStatus.unauthorized,
      'Replayed IdP assertion was accepted',
    );
    _require(
      _jsonMap(replay.json())['error'] == 'saml_authentication_failed',
      'Replay rejection was not generic',
    );

    stdout.writeln('PASS: Keycloak issued a signed SAML response.');
    stdout.writeln('PASS: AuthPortableSamlXmlDsigVerifier accepted it.');
    stdout.writeln('PASS: typed provider path and host session are bound.');
    stdout.writeln('PASS: wrong provider path and assertion replay reject.');
  } finally {
    await routed?.close();
    await engine?.close();
    idp.close();
  }
}

String? _option(List<String> arguments, String name) {
  for (var index = 0; index < arguments.length; index += 1) {
    if (arguments[index] == name && index + 1 < arguments.length) {
      return arguments[index + 1];
    }
    if (arguments[index].startsWith('$name=')) {
      return arguments[index].substring(name.length + 1);
    }
  }
  return null;
}

Future<_Page> _waitForKeycloak(_Browser browser, Uri descriptorUrl) async {
  Object? lastError;
  for (var attempt = 0; attempt < 90; attempt += 1) {
    try {
      final response = await browser.get(descriptorUrl);
      if (response.statusCode == HttpStatus.ok &&
          response.body.contains('EntityDescriptor')) {
        return response;
      }
      lastError = 'HTTP ${response.statusCode}';
    } catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('Keycloak did not become ready: $lastError');
}

String _firstSigningCertificate(String descriptor) {
  final match = RegExp(
    r'<(?:[A-Za-z_][\w.-]*:)?X509Certificate[^>]*>'
    r'([\s\S]*?)'
    r'</(?:[A-Za-z_][\w.-]*:)?X509Certificate>',
  ).firstMatch(descriptor);
  if (match == null) throw StateError('IdP signing certificate is missing');
  final compact = match.group(1)!.replaceAll(RegExp(r'\s'), '');
  final der = base64.decode(compact);
  if (der.isEmpty) throw StateError('IdP signing certificate is empty');
  final lines = <String>[];
  for (var offset = 0; offset < compact.length; offset += 64) {
    final end = (offset + 64).clamp(0, compact.length);
    lines.add(compact.substring(offset, end));
  }
  return '-----BEGIN CERTIFICATE-----\n'
      '${lines.join('\n')}\n'
      '-----END CERTIFICATE-----\n';
}

_HtmlForm _formContaining(_Page page, String selector) {
  final document = html_parser.parse(page.body);
  final forms = document.querySelectorAll('form');
  for (final form in forms) {
    if (form.querySelector(selector) == null) continue;
    final action = form.attributes['action'];
    if (action == null || action.isEmpty) {
      throw StateError('HTML form action is missing');
    }
    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name'];
      if (name != null && name.isNotEmpty) {
        fields[name] = input.attributes['value'] ?? '';
      }
    }
    return _HtmlForm(
      action: page.uri.resolve(action),
      fields: Map.unmodifiable(fields),
    );
  }
  throw StateError('Expected HTML form containing $selector');
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is! Map) throw StateError('Expected a JSON object');
  return Map<String, dynamic>.from(value);
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) throw StateError('Expected a string map');
  return <String, String>{
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class _Catalog implements AuthSamlConnectionCatalog {
  const _Catalog(this.connection);

  final AuthSamlConnection connection;

  @override
  AuthSamlConnection? findByProviderId(String providerId) =>
      providerId == connection.providerId ? connection : null;

  @override
  AuthSamlConnection? findByOrganizationSlug(String slug) => null;

  @override
  AuthSamlConnection? findByVerifiedDomain(String domain) => null;
}

final class _IdentityResolver
    implements AuthSamlIdentityResolver<EngineContext> {
  _IdentityResolver(this.user);

  final AuthUser user;
  AuthSamlAccountIdentity? identity;

  @override
  AuthUser resolveOrProvision(AuthSamlIdentityInput<EngineContext> input) {
    identity = input.identity;
    return user;
  }
}

final class _HtmlForm {
  const _HtmlForm({required this.action, required this.fields});

  final Uri action;
  final Map<String, String> fields;
}

final class _Page {
  const _Page({
    required this.uri,
    required this.statusCode,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final String body;
}

final class _Browser {
  _Browser() {
    _client.badCertificateCallback = (_, _, _) => true;
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  final HttpClient _client = HttpClient();
  final Map<String, Cookie> _cookies = <String, Cookie>{};

  Future<_Page> get(Uri uri) => _send('GET', uri);

  Future<_Page> postForm(Uri uri, Map<String, String> fields) =>
      _send('POST', uri, fields: fields);

  Future<_Page> _send(
    String method,
    Uri uri, {
    Map<String, String>? fields,
    int redirects = 0,
  }) async {
    if (redirects > 12) throw StateError('Too many IdP redirects');
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    if (_cookies.isNotEmpty) request.cookies.addAll(_cookies.values);
    if (fields != null) {
      final body = Uri(queryParameters: fields).query;
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.contentLength = utf8.encode(body).length;
      request.write(body);
    }
    final response = await request.close();
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie;
    }
    final body = await utf8.decoder.bind(response).join();
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (location != null &&
        response.statusCode >= 300 &&
        response.statusCode < 400) {
      return _send('GET', uri.resolve(location), redirects: redirects + 1);
    }
    return _Page(uri: uri, statusCode: response.statusCode, body: body);
  }

  void close() => _client.close(force: true);
}
