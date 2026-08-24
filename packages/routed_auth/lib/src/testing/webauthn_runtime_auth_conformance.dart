import 'dart:convert';

import 'package:routed_auth/src/testing/runtime_auth_conformance.dart';
import 'package:server_auth/testing.dart' show AuthWebAuthnCeremonyFixture;

const _browserOrigin = 'https://runtime.example';
const _relyingPartyId = 'runtime.example';

/// Verifies a successful browser-shaped passkey ceremony through one host.
///
/// [transportOrigin] is the URL of the host adapter under test. The WebAuthn
/// payload retains the fixture's secure browser RP origin so an ephemeral
/// plain-HTTP IO listener can carry the same deterministic browser JSON.
Future<void> verifyAuthWebAuthnBrowserRuntimeConformance({
  required Uri transportOrigin,
  required AuthRuntimeConformanceSend send,
  required String sessionCookie,
  required String sessionCookieName,
  required String csrfToken,
  required String expectedUserEmail,
}) async {
  final registrationOptions = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/register/options',
      headers: _jsonHeaders(
        cookie: sessionCookie,
        origin: transportOrigin.toString(),
      ),
      body: jsonEncode(<String, Object?>{'_csrf': csrfToken}),
    ),
  );
  _expectStatus(registrationOptions, 200, 'webauthn.registration-options');
  final registrationBody = _jsonObject(
    registrationOptions,
    'webauthn.registration-options',
  );
  final relyingParty = registrationBody['rp'];
  final registrationUser = registrationBody['user'];
  _check(
    registrationBody['challenge'] is String &&
        (registrationBody['challenge']! as String).isNotEmpty &&
        relyingParty is Map<String, Object?> &&
        relyingParty['id'] == _relyingPartyId &&
        registrationUser is Map<String, Object?> &&
        registrationUser['id'] is String,
    'webauthn.registration-options',
    'Registration options omitted browser ceremony fields.',
  );
  final registrationUserMap = switch (registrationUser) {
    final Map<String, Object?> value => value,
    _ => throw const AuthRuntimeConformanceFailure(
      caseId: 'webauthn.registration-options',
      message: 'Registration options omitted browser ceremony fields.',
    ),
  };
  final registrationUserId = switch (registrationUserMap['id']) {
    final String value => value,
    _ => throw const AuthRuntimeConformanceFailure(
      caseId: 'webauthn.registration-options',
      message: 'Registration options omitted browser ceremony fields.',
    ),
  };

  final fixture = AuthWebAuthnCeremonyFixture(
    relyingPartyId: _relyingPartyId,
    origin: Uri.parse(_browserOrigin),
  );
  final registered = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/register/verify',
      headers: _jsonHeaders(
        cookie: sessionCookie,
        origin: transportOrigin.toString(),
      ),
      body: jsonEncode(<String, Object?>{
        'credential': fixture.registrationCredential(
          challenge: registrationBody['challenge']! as String,
        ),
        '_csrf': csrfToken,
      }),
    ),
  );
  _expectStatus(registered, 200, 'webauthn.registration-verify');
  final registeredCredential = _jsonObject(
    registered,
    'webauthn.registration-verify',
  )['credential'];
  _check(
    registeredCredential is Map<String, Object?> &&
        registeredCredential['credential_id'] == fixture.credentialId,
    'webauthn.registration-verify',
    'Registration did not persist the browser credential.',
  );

  final authenticationOptions = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/authenticate/options',
      headers: _jsonHeaders(),
      body: '{}',
    ),
  );
  _expectStatus(authenticationOptions, 200, 'webauthn.authentication-options');
  final authenticationBody = _jsonObject(
    authenticationOptions,
    'webauthn.authentication-options',
  );
  _check(
    authenticationBody['challenge'] is String &&
        (authenticationBody['challenge']! as String).isNotEmpty,
    'webauthn.authentication-options',
    'Authentication options omitted the browser challenge.',
  );
  final assertion = fixture.assertionCredential(
    challenge: authenticationBody['challenge']! as String,
    counter: 1,
    userHandle: registrationUserId,
  );
  _check(
    fixture.hasDerEs256Signature(assertion),
    'webauthn.authentication-assertion',
    'Assertion was not encoded as a browser ASN.1 DER signature.',
  );

  final authenticated = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/authenticate/verify',
      headers: _jsonHeaders(),
      body: jsonEncode(<String, Object?>{'credential': assertion}),
    ),
  );
  _expectStatus(authenticated, 200, 'webauthn.authentication-verify');
  final authenticatedBody = _jsonObject(
    authenticated,
    'webauthn.authentication-verify',
  );
  _check(
    _userField(authenticatedBody, 'email') == expectedUserEmail &&
        (authenticatedBody['credential'] as Map?)?['counter'] == 1,
    'webauthn.authentication-verify',
    'Authentication did not resolve the user and advance the counter.',
  );
  _requireSessionCookie(
    authenticated,
    caseId: 'webauthn.authentication-verify',
    cookieName: sessionCookieName,
  );

  final replayedChallenge = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/authenticate/verify',
      headers: _jsonHeaders(),
      body: jsonEncode(<String, Object?>{'credential': assertion}),
    ),
  );
  _expectSanitizedWebAuthnError(
    replayedChallenge,
    'webauthn.challenge-replay',
    expectedError: 'webauthn_challenge_invalid',
    sensitiveValue: fixture.credentialId,
  );

  final counterOptions = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/authenticate/options',
      headers: _jsonHeaders(),
      body: '{}',
    ),
  );
  _expectStatus(counterOptions, 200, 'webauthn.counter-options');
  final staleCounterAssertion = fixture.assertionCredential(
    challenge:
        _jsonObject(counterOptions, 'webauthn.counter-options')['challenge']!
            as String,
    counter: 1,
    userHandle: registrationUserId,
  );
  final replayedCounter = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/authenticate/verify',
      headers: _jsonHeaders(),
      body: jsonEncode(<String, Object?>{'credential': staleCounterAssertion}),
    ),
  );
  _expectSanitizedWebAuthnError(
    replayedCounter,
    'webauthn.counter-replay',
    expectedError: 'webauthn_counter_replay',
    sensitiveValue: fixture.credentialId,
  );
}

Map<String, List<String>> _jsonHeaders({String? cookie, String? origin}) =>
    <String, List<String>>{
      'content-type': const <String>['application/json'],
      if (cookie != null) 'cookie': <String>[cookie],
      if (origin != null) ...<String, List<String>>{
        'origin': <String>[origin],
        'sec-fetch-site': const <String>['same-origin'],
      },
    };

Map<String, Object?> _jsonObject(
  AuthRuntimeConformanceResponse response,
  String caseId,
) {
  Object? value;
  try {
    value = response.json;
  } on FormatException catch (error) {
    throw AuthRuntimeConformanceFailure(
      caseId: caseId,
      message: 'Expected a JSON object: $error',
    );
  }
  _check(value is Map<String, Object?>, caseId, 'Expected a JSON object.');
  return value! as Map<String, Object?>;
}

Object? _userField(Map<String, Object?> body, String field) {
  final user = body['user'];
  return user is Map<String, Object?> ? user[field] : null;
}

void _expectStatus(
  AuthRuntimeConformanceResponse response,
  int statusCode,
  String caseId,
) {
  _check(
    response.statusCode == statusCode,
    caseId,
    'Expected status $statusCode, received ${response.statusCode}: '
    '${response.body}',
  );
}

void _expectSanitizedWebAuthnError(
  AuthRuntimeConformanceResponse response,
  String caseId, {
  required String expectedError,
  required String sensitiveValue,
}) {
  _expectStatus(response, 401, caseId);
  final body = _jsonObject(response, caseId);
  _check(
    body.length == 1 &&
        body['error'] == expectedError &&
        !response.body.contains('StateError') &&
        !response.body.contains('/src/') &&
        !response.body.contains(sensitiveValue),
    caseId,
    'WebAuthn failure leaked credential or implementation details.',
  );
}

void _requireSessionCookie(
  AuthRuntimeConformanceResponse response, {
  required String caseId,
  required String cookieName,
}) {
  final prefix = '$cookieName=';
  for (final value in response.headerValues('set-cookie')) {
    if (value.trimLeft().startsWith(prefix)) return;
  }
  throw AuthRuntimeConformanceFailure(
    caseId: caseId,
    message: 'Expected a $cookieName cookie.',
  );
}

void _check(bool condition, String caseId, String message) {
  if (!condition) {
    throw AuthRuntimeConformanceFailure(caseId: caseId, message: message);
  }
}
