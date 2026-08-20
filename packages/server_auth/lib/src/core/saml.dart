import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:xml/xml.dart';

import 'exceptions.dart';
import 'plugin.dart';
import 'rate_limit.dart';
import 'saml_models.dart';
import 'saml_store.dart';
import 'tokens.dart' show secureRandomToken;

const _samlProtocol = 'urn:oasis:names:tc:SAML:2.0:protocol';
const _samlAssertion = 'urn:oasis:names:tc:SAML:2.0:assertion';
const _samlPostBinding = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST';
const _samlBearer = 'urn:oasis:names:tc:SAML:2.0:cm:bearer';

typedef AuthSamlBrowserBindingResolver<TContext> =
    FutureOr<String> Function(TContext context);

final class AuthSamlLimits {
  const AuthSamlLimits({
    this.maxEncodedResponseBytes = 384 * 1024,
    this.maxDecodedXmlBytes = 256 * 1024,
    this.maxMetadataBytes = 100 * 1024,
    this.maxNodes = 2048,
    this.maxDepth = 24,
    this.maxAttributes = 4096,
    this.maxTextBytes = 128 * 1024,
  });

  final int maxEncodedResponseBytes;
  final int maxDecodedXmlBytes;
  final int maxMetadataBytes;
  final int maxNodes;
  final int maxDepth;
  final int maxAttributes;
  final int maxTextBytes;
}

final class AuthSamlOptions {
  const AuthSamlOptions({
    this.requestTtl = const Duration(minutes: 5),
    this.clockSkew = const Duration(minutes: 1),
    this.maximumAssertionLifetime = const Duration(minutes: 10),
    this.limits = const AuthSamlLimits(),
    this.redirectPolicy = const AuthSamlRedirectPolicy.relativeOnly(),
    this.idpInitiated = const AuthSamlIdpInitiatedPolicy.disabled(),
    this.allowInMemoryStoreForTesting = false,
  });

  final Duration requestTtl;
  final Duration clockSkew;
  final Duration maximumAssertionLifetime;
  final AuthSamlLimits limits;
  final AuthSamlRedirectPolicy redirectPolicy;
  final AuthSamlIdpInitiatedPolicy idpInitiated;
  final bool allowInMemoryStoreForTesting;
}

/// Optional SAML 2.0 SSO server plugin.
///
/// XML signature verification is deliberately application-owned. Routed does
/// not ship a verifier until a portable implementation can prove exact signed
/// reference binding and hostile XML behavior.
final class AuthSamlPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor {
  AuthSamlPlugin({
    required this.connections,
    required this.replayStore,
    required this.assertionVerifier,
    required this.identityResolver,
    required this.browserBindingResolver,
    this.options = const AuthSamlOptions(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (options.requestTtl <= Duration.zero ||
        options.clockSkew < Duration.zero ||
        options.maximumAssertionLifetime <= Duration.zero) {
      throw ArgumentError('SAML durations must be positive');
    }
    if (replayStore is! AuthDurableSamlReplayStore &&
        !options.allowInMemoryStoreForTesting) {
      throw StateError(
        'AuthSamlPlugin requires a durable atomic replay store. '
        'The in-memory store is test-only.',
      );
    }
  }

  final AuthSamlConnectionCatalog connections;
  final AuthSamlReplayStore replayStore;
  final AuthSamlAssertionVerifier assertionVerifier;
  final AuthSamlIdentityResolver<TContext> identityResolver;
  final AuthSamlBrowserBindingResolver<TContext> browserBindingResolver;
  final AuthSamlOptions options;
  final DateTime Function() _clock;

  @override
  String get id => authSamlPluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {}

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    _endpoint(
      id: 'saml.metadata',
      method: AuthOperationMethod.get,
      path: '/sso/saml/metadata/{providerId}',
      semantics: const AuthOperationSemantics.readOnly(),
      handler: _metadata,
    ),
    _endpoint(
      id: 'saml.signIn',
      method: AuthOperationMethod.post,
      path: '/sso/saml/sign-in',
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authSamlPluginId,
            atomicOperationId: 'create-authentication-attempt',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.repeatable,
      ),
      rateLimitOperation: const AuthRateLimitOperation('saml', 'sign-in'),
      handler: _signIn,
    ),
    _endpoint(
      id: 'saml.acs',
      method: AuthOperationMethod.post,
      path: '/sso/saml/acs/{providerId}',
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authSamlPluginId,
            atomicOperationId: 'consume-response',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.singleUse,
      ),
      rateLimitOperation: const AuthRateLimitOperation('saml', 'acs'),
      handler: _acs,
    ),
  ];

  TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>
  _endpoint({
    required String id,
    required AuthOperationMethod method,
    required String path,
    required AuthOperationSemantics semantics,
    required FutureOr<Object?> Function(
      AuthOperationInvocation<TContext>,
      Map<String, dynamic>,
    )
    handler,
    AuthRateLimitOperation? rateLimitOperation,
  }) => TypedAuthEndpointDescriptor(
    id: id,
    method: method,
    path: path,
    semantics: semantics,
    requestCodec: AuthOperationCodec(
      decode: _identityMap,
      encode: _identityMap,
      contentType: id == 'saml.acs'
          ? 'application/x-www-form-urlencoded'
          : 'application/json',
      schema: _requestSchema(id),
    ),
    responseCodec: AuthOperationCodec(
      decode: _identityObject,
      encode: _identityObject,
      contentType: id == 'saml.metadata'
          ? 'application/samlmetadata+xml'
          : 'application/json',
      schema: _responseSchema(id),
    ),
    handler: handler,
    authentication: AuthOperationAuthentication.none,
    originPolicy: id == 'saml.signIn'
        ? AuthOperationOriginPolicy.browser
        : AuthOperationOriginPolicy.none,
    csrfPolicy: id == 'saml.signIn'
        ? AuthOperationCsrfPolicy.required
        : AuthOperationCsrfPolicy.none,
    rateLimitOperation: rateLimitOperation,
  );

  Future<Object?> _metadata(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> request,
  ) async {
    final connection = await _connectionByProvider(
      _required(request, 'providerId'),
    );
    final document = _metadataDocument(connection);
    if (utf8.encode(document).length > options.limits.maxMetadataBytes) {
      throw AuthFlowException('saml_authentication_failed');
    }
    return AuthEndpointProtocolResponse(
      body: document,
      contentType: 'application/samlmetadata+xml; charset=utf-8',
      headers: const {'cache-control': 'no-store'},
    );
  }

  Future<Object?> _signIn(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> request,
  ) async {
    try {
      final connection = await _resolveSelector(request);
      final browserBinding = await _browserBinding(invocation.context);
      final callback = options.redirectPolicy.project(
        request['callbackUrl']?.toString(),
        fallback: Uri(path: '/'),
      );
      final now = _clock().toUtc();
      final requestId = '_${secureRandomToken(length: 32)}';
      final relayState = secureRandomToken(length: 43);
      await replayStore.createAttempt(
        AuthSamlAuthenticationAttempt(
          providerId: connection.providerId,
          requestId: requestId,
          relayStateHash: _digest(relayState),
          browserBindingHash: _digest(browserBinding),
          callback: callback,
          createdAt: now,
          expiresAt: now.add(options.requestTtl),
        ),
      );
      final authnRequest = _authnRequest(connection, requestId, now);
      return <String, dynamic>{
        'providerId': connection.providerId,
        'binding': _samlPostBinding,
        'destination': connection.idpSsoUrl.toString(),
        'fields': <String, String>{
          'SAMLRequest': base64.encode(utf8.encode(authnRequest)),
          'RelayState': relayState,
        },
      };
    } catch (error) {
      if (error is AuthFlowException) rethrow;
      throw AuthFlowException('saml_authentication_failed');
    }
  }

  Future<Object?> _acs(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> request,
  ) async {
    try {
      final providerId = _required(request, 'providerId');
      final connection = await _connectionByProvider(providerId);
      final encodedResponse = request['SAMLResponse']?.toString() ?? '';
      if (encodedResponse.isEmpty) {
        throw const FormatException('missing SAMLResponse');
      }
      final parsed = _parseResponse(encodedResponse, connection);
      final proof = await assertionVerifier.verify(
        AuthSamlVerificationInput(
          xml: parsed.xml,
          connection: connection,
          responseId: parsed.responseId,
          assertionId: parsed.assertionId,
        ),
      );
      _validateSignatureProof(proof, parsed);
      final now = _clock().toUtc();
      final relayState = request['RelayState']?.toString().trim() ?? '';
      Uri callback;
      if (parsed.inResponseTo != null) {
        if (relayState.isEmpty || relayState.length > 512) {
          throw const FormatException('missing relay state');
        }
        final browserBinding = await _browserBinding(invocation.context);
        final result = await replayStore.consumeSpInitiated(
          providerId: providerId,
          requestId: parsed.inResponseTo!,
          relayStateHash: _digest(relayState),
          browserBindingHash: _digest(browserBinding),
          assertionId: parsed.assertionId,
          assertionExpiresAt: parsed.expiresAt,
          now: now,
        );
        if (!result.accepted) throw const FormatException('rejected response');
        callback = result.attempt!.callback;
      } else {
        final policy = options.idpInitiated;
        if (policy is! AuthSamlIdpInitiatedFixedCallback ||
            relayState.isNotEmpty) {
          throw const FormatException('IdP initiated disabled');
        }
        if (!await replayStore.consumeIdpInitiated(
          providerId: providerId,
          assertionId: parsed.assertionId,
          assertionExpiresAt: parsed.expiresAt,
          now: now,
        )) {
          throw const FormatException('replayed assertion');
        }
        callback = options.redirectPolicy.project(
          policy.callback.toString(),
          fallback: policy.callback,
        );
      }
      final identity = AuthSamlAccountIdentity(
        providerId: providerId,
        idpEntityId: connection.idpEntityId,
        nameId: parsed.nameId,
        nameIdFormat: parsed.nameIdFormat,
      );
      final user = await identityResolver.resolveOrProvision(
        AuthSamlIdentityInput(
          invocation: invocation,
          connection: connection,
          identity: identity,
          attributes: parsed.attributes,
        ),
      );
      return AuthEndpointAuthenticationIntent(
        user: user,
        authenticationMethod: 'saml:${connection.providerId}',
        metadata: <String, dynamic>{'status': 'authenticated'},
        projectResponse: (_) => AuthEndpointRedirect(location: callback),
      );
    } catch (_) {
      throw AuthFlowException('saml_authentication_failed');
    }
  }

  Future<AuthSamlConnection> _resolveSelector(
    Map<String, dynamic> request,
  ) async {
    final values = <String, String>{
      for (final key in ['providerId', 'domain', 'organizationSlug'])
        if ((request[key]?.toString().trim() ?? '').isNotEmpty)
          key: request[key].toString().trim(),
    };
    if (values.length != 1) {
      throw const FormatException('one selector required');
    }
    final entry = values.entries.single;
    final connection = switch (entry.key) {
      'providerId' => await connections.findByProviderId(entry.value),
      'domain' => await connections.findByVerifiedDomain(
        normalizeAuthSamlDomain(entry.value),
      ),
      'organizationSlug' => await connections.findByOrganizationSlug(
        entry.value,
      ),
      _ => null,
    };
    if (connection == null) {
      throw AuthFlowException('saml_authentication_failed');
    }
    if (entry.key == 'domain' &&
        !connection.verifiedDomains.contains(
          normalizeAuthSamlDomain(entry.value),
        )) {
      throw AuthFlowException('saml_authentication_failed');
    }
    return connection;
  }

  Future<AuthSamlConnection> _connectionByProvider(String providerId) async {
    final connection = await connections.findByProviderId(providerId);
    if (connection == null || connection.providerId != providerId) {
      throw AuthFlowException('saml_authentication_failed');
    }
    return connection;
  }

  Future<String> _browserBinding(TContext context) async {
    final value = (await browserBindingResolver(context)).trim();
    if (value.length < 16 || value.length > 1024) {
      throw AuthFlowException('saml_authentication_failed');
    }
    return value;
  }

  _ParsedSamlResponse _parseResponse(
    String encoded,
    AuthSamlConnection connection,
  ) {
    final limits = options.limits;
    if (utf8.encode(encoded).length > limits.maxEncodedResponseBytes) {
      throw const FormatException('response too large');
    }
    final bytes = base64.decode(base64.normalize(encoded));
    if (bytes.length > limits.maxDecodedXmlBytes) {
      throw const FormatException('xml too large');
    }
    final xml = utf8.decode(bytes, allowMalformed: false);
    final lower = xml.toLowerCase();
    if (lower.contains('<!doctype') || lower.contains('<!entity')) {
      throw const FormatException('DTD and entities are forbidden');
    }
    final document = XmlDocument.parse(xml);
    _enforceXmlBounds(document, limits);
    final response = document.rootElement;
    _expectName(response, 'Response', _samlProtocol);
    if (_requiredAttribute(response, 'Version') != '2.0') {
      throw const FormatException('unsupported SAML version');
    }
    final responseIssueInstant = _requiredTime(response, 'IssueInstant');
    final status = _singleChild(response, 'Status', _samlProtocol);
    final statusCode = _singleChild(status, 'StatusCode', _samlProtocol);
    if (_requiredAttribute(statusCode, 'Value') !=
        'urn:oasis:names:tc:SAML:2.0:status:Success') {
      throw const FormatException('SAML response was not successful');
    }
    final assertions = response.childElements
        .where((node) => _hasName(node, 'Assertion', _samlAssertion))
        .toList(growable: false);
    if (assertions.length != 1) {
      throw const FormatException('one assertion required');
    }
    final assertion = assertions.single;
    if (_requiredAttribute(assertion, 'Version') != '2.0') {
      throw const FormatException('unsupported SAML version');
    }
    final assertionIssueInstant = _requiredTime(assertion, 'IssueInstant');
    _rejectDuplicateIds(document);
    final responseId = _requiredAttribute(response, 'ID');
    final assertionId = _requiredAttribute(assertion, 'ID');
    final destination = _requiredAttribute(response, 'Destination');
    if (destination != connection.assertionConsumerServiceUrl.toString()) {
      throw const FormatException('destination mismatch');
    }
    final responseIssuer = _singleText(response, 'Issuer', _samlAssertion);
    final assertionIssuer = _singleText(assertion, 'Issuer', _samlAssertion);
    if (responseIssuer != connection.idpEntityId ||
        assertionIssuer != connection.idpEntityId) {
      throw const FormatException('issuer mismatch');
    }
    final subject = _singleChild(assertion, 'Subject', _samlAssertion);
    final nameIdNode = _singleChild(subject, 'NameID', _samlAssertion);
    final nameId = nameIdNode.innerText.trim();
    final nameIdFormat = _requiredAttribute(nameIdNode, 'Format');
    if (nameId.isEmpty ||
        nameId.length > 1024 ||
        nameIdFormat != connection.nameIdFormat.uri) {
      throw const FormatException('invalid NameID');
    }
    final confirmation = _singleChild(
      subject,
      'SubjectConfirmation',
      _samlAssertion,
    );
    if (_requiredAttribute(confirmation, 'Method') != _samlBearer) {
      throw const FormatException('invalid subject confirmation');
    }
    final confirmationData = _singleChild(
      confirmation,
      'SubjectConfirmationData',
      _samlAssertion,
    );
    if (_requiredAttribute(confirmationData, 'Recipient') !=
        connection.assertionConsumerServiceUrl.toString()) {
      throw const FormatException('recipient mismatch');
    }
    final responseInResponseTo = response.getAttribute('InResponseTo')?.trim();
    final subjectInResponseTo = confirmationData
        .getAttribute('InResponseTo')
        ?.trim();
    final inResponseTo = (responseInResponseTo?.isNotEmpty ?? false)
        ? responseInResponseTo
        : null;
    if (inResponseTo != null && subjectInResponseTo != inResponseTo) {
      throw const FormatException('InResponseTo mismatch');
    }
    if (inResponseTo == null && (subjectInResponseTo?.isNotEmpty ?? false)) {
      throw const FormatException('InResponseTo mismatch');
    }
    final conditions = _singleChild(assertion, 'Conditions', _samlAssertion);
    final notBefore = _requiredTime(conditions, 'NotBefore');
    final conditionsExpiry = _requiredTime(conditions, 'NotOnOrAfter');
    final subjectExpiry = _requiredTime(confirmationData, 'NotOnOrAfter');
    final expiresAt = conditionsExpiry.isBefore(subjectExpiry)
        ? conditionsExpiry
        : subjectExpiry;
    final now = _clock().toUtc();
    if (now.add(options.clockSkew).isBefore(notBefore) ||
        !now.subtract(options.clockSkew).isBefore(expiresAt) ||
        responseIssueInstant.isAfter(now.add(options.clockSkew)) ||
        assertionIssueInstant.isAfter(now.add(options.clockSkew)) ||
        responseIssueInstant.isBefore(notBefore.subtract(options.clockSkew)) ||
        assertionIssueInstant.isBefore(notBefore.subtract(options.clockSkew)) ||
        conditionsExpiry.difference(notBefore) >
            options.maximumAssertionLifetime) {
      throw const FormatException('invalid assertion time');
    }
    final audienceRestrictions = conditions.childElements
        .where((node) => _hasName(node, 'AudienceRestriction', _samlAssertion))
        .toList(growable: false);
    if (audienceRestrictions.length != 1) {
      throw const FormatException('one audience restriction required');
    }
    final audiences = audienceRestrictions.single.childElements
        .where((node) => _hasName(node, 'Audience', _samlAssertion))
        .map((node) => node.innerText.trim())
        .toList(growable: false);
    if (audiences.length != 1 || audiences.single != connection.spEntityId) {
      throw const FormatException('audience mismatch');
    }
    return _ParsedSamlResponse(
      xml: xml,
      responseId: responseId,
      assertionId: assertionId,
      inResponseTo: inResponseTo,
      nameId: nameId,
      nameIdFormat: nameIdFormat,
      expiresAt: expiresAt,
      attributes: _attributes(assertion),
    );
  }

  void _validateSignatureProof(
    AuthSamlSignatureProof proof,
    _ParsedSamlResponse parsed,
  ) {
    if ((proof.signedResponseId != null &&
            proof.signedResponseId != parsed.responseId) ||
        (proof.signedAssertionId != null &&
            proof.signedAssertionId != parsed.assertionId) ||
        (proof.signedResponseId == null && proof.signedAssertionId == null)) {
      throw const FormatException('signature reference mismatch');
    }
    const signatures = {
      'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256',
      'http://www.w3.org/2001/04/xmldsig-more#rsa-sha384',
      'http://www.w3.org/2001/04/xmldsig-more#rsa-sha512',
      'http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256',
      'http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384',
      'http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512',
    };
    const digests = {
      'http://www.w3.org/2001/04/xmlenc#sha256',
      'http://www.w3.org/2001/04/xmldsig-more#sha384',
      'http://www.w3.org/2001/04/xmlenc#sha512',
    };
    const canonicalization = {
      'http://www.w3.org/2001/10/xml-exc-c14n#',
      'http://www.w3.org/TR/2001/REC-xml-c14n-20010315',
    };
    if (!signatures.contains(proof.signatureAlgorithm) ||
        !digests.contains(proof.digestAlgorithm) ||
        !canonicalization.contains(proof.canonicalizationAlgorithm)) {
      throw const FormatException('unsupported signature algorithm');
    }
  }

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      serverOnly: endpoint.serverOnly,
    ),
  );

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => const [
    AuthRateLimitOperation('saml', 'sign-in'),
    AuthRateLimitOperation('saml', 'acs'),
  ];

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: authSamlPluginId,
      entities: [
        AuthEntityDescriptor(
          id: 'auth_saml_attempt',
          fields: [
            AuthFieldDescriptor(name: 'providerId', kind: 'string'),
            AuthFieldDescriptor(name: 'requestId', kind: 'id'),
            AuthFieldDescriptor(name: 'relayStateHash', kind: 'digest'),
            AuthFieldDescriptor(name: 'browserBindingHash', kind: 'digest'),
            AuthFieldDescriptor(name: 'callback', kind: 'uri'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
          ],
          uniqueConstraints: [
            ['requestId'],
          ],
          indexes: [
            ['providerId', 'expiresAt'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'auth_saml_assertion_receipt',
          fields: [
            AuthFieldDescriptor(name: 'providerId', kind: 'string'),
            AuthFieldDescriptor(name: 'assertionId', kind: 'id'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
          ],
          uniqueConstraints: [
            ['providerId', 'assertionId'],
          ],
          indexes: [
            ['expiresAt'],
          ],
        ),
      ],
      atomicOperations: [
        AuthAtomicOperationDescriptor(
          id: 'create-authentication-attempt',
          description:
              'Create one bounded provider-bound SAML request and RelayState digest.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'consume-response',
          description:
              'Consume AuthnRequest and RelayState while inserting the assertion replay receipt.',
        ),
      ],
    ),
  ];
}

final class _ParsedSamlResponse {
  const _ParsedSamlResponse({
    required this.xml,
    required this.responseId,
    required this.assertionId,
    required this.inResponseTo,
    required this.nameId,
    required this.nameIdFormat,
    required this.expiresAt,
    required this.attributes,
  });
  final String xml;
  final String responseId;
  final String assertionId;
  final String? inResponseTo;
  final String nameId;
  final String nameIdFormat;
  final DateTime expiresAt;
  final Map<String, List<String>> attributes;
}

String _metadataDocument(AuthSamlConnection connection) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'md:EntityDescriptor',
    nest: () {
      builder.attribute('xmlns:md', 'urn:oasis:names:tc:SAML:2.0:metadata');
      builder.attribute('xmlns:saml', _samlAssertion);
      builder.attribute('entityID', connection.spEntityId);
      builder.element(
        'md:SPSSODescriptor',
        nest: () {
          builder.attribute('AuthnRequestsSigned', 'false');
          builder.attribute('WantAssertionsSigned', 'true');
          builder.attribute('protocolSupportEnumeration', _samlProtocol);
          builder.element('md:NameIDFormat', nest: connection.nameIdFormat.uri);
          builder.element(
            'md:AssertionConsumerService',
            nest: () {
              builder.attribute('Binding', _samlPostBinding);
              builder.attribute(
                'Location',
                connection.assertionConsumerServiceUrl.toString(),
              );
              builder.attribute('index', '0');
              builder.attribute('isDefault', 'true');
            },
          );
        },
      );
    },
  );
  return builder.buildDocument().toXmlString(pretty: false);
}

String _authnRequest(AuthSamlConnection connection, String id, DateTime now) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'samlp:AuthnRequest',
    nest: () {
      builder.attribute('xmlns:samlp', _samlProtocol);
      builder.attribute('xmlns:saml', _samlAssertion);
      builder.attribute('ID', id);
      builder.attribute('Version', '2.0');
      builder.attribute('IssueInstant', now.toIso8601String());
      builder.attribute('Destination', connection.idpSsoUrl.toString());
      builder.attribute(
        'AssertionConsumerServiceURL',
        connection.assertionConsumerServiceUrl.toString(),
      );
      builder.attribute('ProtocolBinding', _samlPostBinding);
      builder.element('saml:Issuer', nest: connection.spEntityId);
      builder.element(
        'samlp:NameIDPolicy',
        nest: () {
          builder.attribute('Format', connection.nameIdFormat.uri);
          builder.attribute('AllowCreate', 'true');
        },
      );
    },
  );
  return builder.buildDocument().toXmlString(pretty: false);
}

void _enforceXmlBounds(XmlDocument document, AuthSamlLimits limits) {
  var nodes = 0;
  var attributes = 0;
  var textBytes = 0;
  void visit(XmlNode node, int depth) {
    nodes++;
    if (nodes > limits.maxNodes || depth > limits.maxDepth) {
      throw const FormatException('XML structure too large');
    }
    if (node is XmlElement) {
      attributes += node.attributes.length;
      if (attributes > limits.maxAttributes) {
        throw const FormatException('too many attributes');
      }
    }
    if (node is XmlText) {
      textBytes += utf8.encode(node.value).length;
      if (textBytes > limits.maxTextBytes) {
        throw const FormatException('XML text too large');
      }
    }
    for (final child in node.children) {
      visit(child, depth + 1);
    }
  }

  visit(document, 0);
}

void _rejectDuplicateIds(XmlDocument document) {
  final seen = <String>{};
  for (final element in document.descendantElements) {
    for (final name in const ['ID', 'Id', 'id']) {
      final value = element.getAttribute(name)?.trim();
      if (value != null && value.isNotEmpty && !seen.add(value)) {
        throw const FormatException('duplicate XML ID');
      }
    }
  }
}

Map<String, List<String>> _attributes(XmlElement assertion) {
  final statements = assertion.childElements.where(
    (node) => _hasName(node, 'AttributeStatement', _samlAssertion),
  );
  final result = <String, List<String>>{};
  for (final statement in statements) {
    for (final attribute in statement.childElements.where(
      (node) => _hasName(node, 'Attribute', _samlAssertion),
    )) {
      final name = attribute.getAttribute('Name')?.trim() ?? '';
      if (name.isEmpty || name.length > 256 || result.containsKey(name)) {
        throw const FormatException('invalid SAML attribute');
      }
      final values = attribute.childElements
          .where((node) => _hasName(node, 'AttributeValue', _samlAssertion))
          .map((node) => node.innerText.trim())
          .where((value) => value.isNotEmpty && value.length <= 4096)
          .toList(growable: false);
      result[name] = List<String>.unmodifiable(values);
    }
  }
  return Map<String, List<String>>.unmodifiable(result);
}

XmlElement _singleChild(XmlElement parent, String local, String namespace) {
  final matches = parent.childElements
      .where((node) => _hasName(node, local, namespace))
      .toList(growable: false);
  if (matches.length != 1) throw FormatException('one $local required');
  return matches.single;
}

String _singleText(XmlElement parent, String local, String namespace) {
  final value = _singleChild(parent, local, namespace).innerText.trim();
  if (value.isEmpty || value.length > 1024) {
    throw FormatException('invalid $local');
  }
  return value;
}

bool _hasName(XmlElement node, String local, String namespace) =>
    node.name.local == local && node.name.namespaceUri == namespace;

void _expectName(XmlElement node, String local, String namespace) {
  if (!_hasName(node, local, namespace)) {
    throw const FormatException('unexpected root');
  }
}

String _requiredAttribute(XmlElement element, String name) {
  final value = element.getAttribute(name)?.trim() ?? '';
  if (value.isEmpty || value.length > 2048) {
    throw FormatException('missing $name');
  }
  return value;
}

DateTime _requiredTime(XmlElement element, String name) {
  final raw = _requiredAttribute(element, name);
  final value = DateTime.tryParse(raw);
  if (value == null || !raw.endsWith('Z')) {
    throw FormatException('invalid $name');
  }
  return value.toUtc();
}

String _required(Map<String, dynamic> value, String key) {
  final result = value[key]?.toString().trim() ?? '';
  if (result.isEmpty || result.length > 1024) {
    throw FormatException('missing $key');
  }
  return result;
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
Map<String, dynamic> _identityMap(Map<String, dynamic> value) => value;
Object? _identityObject(Object? value) => value;

Map<String, Object?> _requestSchema(String id) => switch (id) {
  'saml.metadata' => const {
    'type': 'object',
    'properties': {
      'providerId': {'type': 'string'},
    },
    'required': ['providerId'],
  },
  'saml.signIn' => const {
    'type': 'object',
    'properties': {
      'providerId': {'type': 'string'},
      'domain': {'type': 'string'},
      'organizationSlug': {'type': 'string'},
      'callbackUrl': {'type': 'string'},
    },
  },
  _ => const {
    'type': 'object',
    'properties': {
      'providerId': {'type': 'string'},
      'SAMLResponse': {'type': 'string'},
      'RelayState': {'type': 'string'},
    },
    'required': ['providerId', 'SAMLResponse'],
  },
};

Map<String, Object?> _responseSchema(String id) => switch (id) {
  'saml.metadata' => const {'type': 'string'},
  'saml.signIn' => const {
    'type': 'object',
    'required': ['providerId', 'binding', 'destination', 'fields'],
  },
  _ => const {'type': 'object'},
};
