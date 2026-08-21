import 'package:routed_openapi/server_auth.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthPluginOpenApiGenerator', () {
    test('generates built-in plugin operations from the frozen registry', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
      ]);

      final spec = registry.toOpenApi31(info: _info);

      expect(spec.openapi, '3.1.0');
      expect(
        spec.paths.keys,
        containsAll(<String>[
          '/auth/sign-in/anonymous',
          '/auth/delete-anonymous-user',
        ]),
      );

      final signIn = spec.paths['/auth/sign-in/anonymous']!.post!;
      expect(signIn.operationId, 'authAnonymousSignIn');
      expect(signIn.tags, <String>['anonymous']);
      expect(signIn.security, isEmpty);
      expect(signIn.responses.keys, containsAll(<String>['200', '429']));
      expect(
        signIn.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'atomic',
          'replaySafety': 'repeatable',
          'persistenceReference': <String, Object?>{
            'schemaId': 'anonymous',
            'atomicOperationId': 'anonymous.createAccount',
          },
        },
      );

      final delete = spec.paths['/auth/delete-anonymous-user']!.post!;
      expect(delete.operationId, 'authAnonymousDelete');
      expect(delete.security, const <Map<String, List<String>>>[
        <String, List<String>>{
          AuthPluginOpenApiGenerator.sessionCookieSecurityScheme: <String>[],
        },
        <String, List<String>>{
          AuthPluginOpenApiGenerator.bearerSecurityScheme: <String>[],
        },
      ]);
      expect(
        spec.components!.securitySchemes.keys,
        containsAll(<String>['authSessionCookie', 'authBearer']),
      );
      expect(
        spec.components!.schemas.keys,
        containsAll(<String>[
          'AuthAnonymousSignInRequest',
          'AuthAnonymousSignInResponse',
          'AuthAnonymousDeleteRequest',
          'AuthAnonymousDeleteResponse',
        ]),
      );
      _expectGeneratedClientCompatible(spec);
    });

    test('preserves atomic organization replay semantics', () {
      final spec = _registry(<AuthServerPlugin<Object>>[
        OrganizationPlugin<Object>(store: InMemoryAuthOrganizationStore()),
      ]).toOpenApi31(info: _info);

      final invite = spec.paths['/auth/organization/invite-member']!.post!;
      expect(
        invite.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'atomic',
          'replaySafety': 'idempotent',
          'persistenceReference': <String, Object?>{
            'schemaId': 'organization',
            'atomicOperationId': 'createInvitation',
          },
        },
      );
      final update = spec.paths['/auth/organization/update']!.post!;
      expect(
        update.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'nonAtomic',
          'replaySafety': 'idempotent',
          'persistenceReference': <String, Object?>{'schemaId': 'organization'},
        },
      );
    });

    test('preserves atomic phone issue and verification semantics', () {
      final spec = _registry(<AuthServerPlugin<Object>>[
        PhoneNumberPlugin<Object>(
          sendCode: (_) {},
          codeHashKey: 'openapi-phone-code-key-32-bytes-minimum',
        ),
      ]).toOpenApi31(info: _info);

      final issue = spec.paths['/auth/phone-number/send-code']!.post!;
      expect(
        issue.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'atomic',
          'replaySafety': 'repeatable',
          'persistenceReference': <String, Object?>{
            'schemaId': 'phone_number',
            'atomicOperationId': 'phoneNumber.issueCode',
          },
        },
      );
      final verify = spec.paths['/auth/phone-number/verify-code']!.post!;
      expect(
        verify.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'atomic',
          'replaySafety': 'singleUse',
          'persistenceReference': <String, Object?>{
            'schemaId': 'phone_number',
            'atomicOperationId': 'phoneNumber.verifyCode',
          },
        },
      );
      expect(
        spec.components!.schemas.keys,
        containsAll(<String>[
          'AuthPhoneNumberSendCodeRequest',
          'AuthPhoneNumberSendCodeResponse',
          'AuthPhoneNumberVerifyCodeRequest',
          'AuthPhoneNumberVerifyCodeResponse',
        ]),
      );
    });

    test('composed plugin additions appear without a route catalogue', () {
      final withoutMagicLink = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
      ]).toOpenApi31(info: _info);
      final withMagicLink = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
        const _ContractPlugin(
          id: 'magic_link',
          endpoints: <_EndpointContract>[
            _EndpointContract(
              id: 'magicLink.send',
              method: AuthOperationMethod.post,
              path: '/magic-link/send',
              semantics: AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.external(),
                replaySafety: AuthMutationReplaySafety.repeatable,
              ),
              requestSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'email': <String, Object?>{
                    'type': 'string',
                    'format': 'email',
                  },
                },
                'required': <String>['email'],
                'additionalProperties': false,
              },
              responseSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'accepted': <String, Object?>{'type': 'boolean'},
                },
                'required': <String>['accepted'],
              },
              requestRequired: true,
              csrfRequired: true,
            ),
          ],
        ),
      ]).toOpenApi31(info: _info);

      expect(withoutMagicLink.paths, isNot(contains('/auth/magic-link/send')));
      final operation = withMagicLink.paths['/auth/magic-link/send']!.post!;
      expect(operation.operationId, 'authMagicLinkSend');
      expect(operation.tags, <String>['magic_link']);
      expect(operation.requestBody!.required, isTrue);
      expect(
        operation.parameters.map((parameter) => parameter.name),
        containsAll(<String>['Origin', 'x-csrf-token']),
      );
      expect(operation.responses.keys, containsAll(<String>['200', '403']));
      expect(
        withMagicLink.components!.schemas['AuthMagicLinkSendRequest'],
        containsPair('additionalProperties', false),
      );
      _expectGeneratedClientCompatible(withMagicLink);
    });

    test('publishes SAML metadata, sign-in, ACS, and replay semantics', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        AuthSamlPlugin<Object>(
          connections: _SamlCatalog(),
          replayStore: InMemoryAuthSamlReplayStore(),
          assertionVerifier: const _SamlVerifier(),
          identityResolver: const _SamlResolver(),
          browserBindingResolver: (_) => 'browser-binding-value',
          options: const AuthSamlOptions(allowInMemoryStoreForTesting: true),
        ),
      ]);
      final spec = registry.toOpenApi31(info: _info);

      expect(
        spec.paths.keys,
        containsAll(<String>[
          '/auth/sso/saml/metadata/{providerId}',
          '/auth/sso/saml/sign-in',
          '/auth/sso/saml/acs/{providerId}',
        ]),
      );
      final signIn = spec.paths['/auth/sso/saml/sign-in']!.post!;
      expect(
        signIn.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'atomic',
          'replaySafety': 'repeatable',
          'persistenceReference': <String, Object?>{
            'schemaId': 'saml_sso',
            'atomicOperationId': 'create-authentication-attempt',
          },
        },
      );
      expect(
        spec
            .paths['/auth/sso/saml/acs/{providerId}']!
            .post!
            .requestBody!
            .content
            .keys,
        contains('application/x-www-form-urlencoded'),
      );
      expect(
        spec
            .paths['/auth/sso/saml/metadata/{providerId}']!
            .get!
            .responses['200']!
            .content!
            .keys,
        contains('application/samlmetadata+xml'),
      );
      _expectGeneratedClientCompatible(spec);
    });

    test('turns typed GET contracts into path and query parameters', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        const _ContractPlugin(
          id: 'tokens',
          endpoints: <_EndpointContract>[
            _EndpointContract(
              id: 'tokens.inspect',
              method: AuthOperationMethod.get,
              path: '/tokens/{id}',
              pathParameters: <AuthRouteParameterKey>[
                AuthRouteParameterKey('id'),
              ],
              semantics: AuthOperationSemantics.readOnly(),
              requestSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'id': <String, Object?>{'type': 'string'},
                  'expand': <String, Object?>{'type': 'boolean'},
                },
                'required': <String>['id'],
              },
              responseSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      ]);

      final operation = registry
          .toOpenApi31(info: _info)
          .paths['/auth/tokens/{id}']!
          .get!;

      expect(
        operation.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        const <String, Object?>{'effect': 'readOnly'},
      );

      expect(
        operation.parameters
            .map((parameter) => '${parameter.location}:${parameter.name}')
            .toList(),
        <String>['path:id', 'query:expand', 'header:Origin'],
      );
      expect(operation.parameters.first.isRequired, isTrue);
      expect(operation.parameters.last.isRequired, isFalse);
      expect(operation.requestBody, isNull);
    });

    test('keeps path parameters out of mutation request bodies', () {
      final spec = _registry(<AuthServerPlugin<Object>>[
        const _ContractPlugin(
          id: 'tokens',
          endpoints: <_EndpointContract>[
            _EndpointContract(
              id: 'tokens.update',
              method: AuthOperationMethod.post,
              path: '/tokens/{id}',
              pathParameters: <AuthRouteParameterKey>[
                AuthRouteParameterKey('id'),
              ],
              semantics: AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.external(),
                replaySafety: AuthMutationReplaySafety.idempotent,
              ),
              requestRequired: true,
              requestSchema: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'id': <String, Object?>{'type': 'string'},
                  'value': <String, Object?>{'type': 'string'},
                },
                'required': <String>['id', 'value'],
              },
              responseSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      ]).toOpenApi31(info: _info);

      final operation = spec.paths['/auth/tokens/{id}']!.post!;
      expect(
        operation.parameters.map((parameter) => parameter.name),
        contains('id'),
      );
      final schema = spec.components!.schemas['AuthTokensUpdateRequest']!;
      expect((schema['properties']! as Map), isNot(contains('id')));
      expect(schema['required'], <String>['value']);
    });

    test('keeps well-known plugin endpoints at the root', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        const _ContractPlugin(
          id: 'metadata',
          endpoints: <_EndpointContract>[
            _EndpointContract(
              id: 'metadata.discovery',
              method: AuthOperationMethod.get,
              path: '/.well-known/auth',
              mount: AuthEndpointMount.root,
              semantics: AuthOperationSemantics.readOnly(),
              requestSchema: <String, Object?>{},
              responseSchema: <String, Object?>{'type': 'object'},
            ),
          ],
        ),
      ]);

      final spec = registry.toOpenApi31(info: _info);

      expect(spec.paths, contains('/.well-known/auth'));
      expect(spec.paths, isNot(contains('/auth/.well-known/auth')));
    });

    test('can advertise bearer-only session authentication', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
      ]);

      final spec = registry.toOpenApi31(
        info: _info,
        config: const AuthPluginOpenApiConfig(
          sessionSecurity: AuthOpenApiSessionSecurity.bearer,
        ),
      );
      final operation = spec.paths['/auth/delete-anonymous-user']!.post!;

      expect(operation.security, const <Map<String, List<String>>>[
        <String, List<String>>{
          AuthPluginOpenApiGenerator.bearerSecurityScheme: <String>[],
        },
      ]);
      expect(spec.components!.securitySchemes, contains('authBearer'));
      expect(
        spec.components!.securitySchemes,
        isNot(contains('authSessionCookie')),
      );
    });

    test('rejects generated-client operation ID collisions', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        const _ContractPlugin(
          id: 'collision',
          endpoints: <_EndpointContract>[
            _EndpointContract(
              id: 'magic-link.send',
              method: AuthOperationMethod.post,
              path: '/magic-link/send',
              semantics: AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.boundedEphemeral(),
                replaySafety: AuthMutationReplaySafety.repeatable,
              ),
              requestSchema: <String, Object?>{},
              responseSchema: <String, Object?>{},
            ),
            _EndpointContract(
              id: 'magic_link.send',
              method: AuthOperationMethod.post,
              path: '/magic-link/send-again',
              semantics: AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.boundedEphemeral(),
                replaySafety: AuthMutationReplaySafety.repeatable,
              ),
              requestSchema: <String, Object?>{},
              responseSchema: <String, Object?>{},
            ),
          ],
        ),
      ]);

      expect(
        () => registry.toOpenApi31(info: _info),
        throwsA(
          isA<AuthOpenApiContractException>().having(
            (error) => error.message,
            'message',
            contains('same operationId "authMagicLinkSend"'),
          ),
        ),
      );
    });

    test('plugin composition rejects duplicate method and path pairs', () {
      expect(
        () => _registry(<AuthServerPlugin<Object>>[
          const _ContractPlugin(
            id: 'duplicate_paths',
            endpoints: <_EndpointContract>[
              _EndpointContract(
                id: 'first.send',
                method: AuthOperationMethod.post,
                path: '/send',
                semantics: AuthOperationSemantics.mutation(
                  persistence: AuthMutationPersistence.boundedEphemeral(),
                  replaySafety: AuthMutationReplaySafety.repeatable,
                ),
                requestSchema: <String, Object?>{},
                responseSchema: <String, Object?>{},
              ),
              _EndpointContract(
                id: 'second.send',
                method: AuthOperationMethod.post,
                path: '/send',
                semantics: AuthOperationSemantics.mutation(
                  persistence: AuthMutationPersistence.boundedEphemeral(),
                  replaySafety: AuthMutationReplaySafety.repeatable,
                ),
                requestSchema: <String, Object?>{},
                responseSchema: <String, Object?>{},
              ),
            ],
          ),
        ]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('post:/send'),
          ),
        ),
      );
    });

    test('server-only plugin operations are opt-in', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        const _ContractPlugin(
          id: 'internal',
          endpoints: <_EndpointContract>[
            _EndpointContract(
              id: 'internal.rotate',
              method: AuthOperationMethod.post,
              path: '/internal/rotate',
              semantics: AuthOperationSemantics.mutation(
                persistence: AuthMutationPersistence.durable(
                  atomicity: AuthMutationAtomicity.nonAtomic,
                ),
                replaySafety: AuthMutationReplaySafety.singleUse,
              ),
              requestSchema: <String, Object?>{},
              responseSchema: <String, Object?>{},
              serverOnly: true,
            ),
          ],
        ),
      ]);

      expect(registry.toOpenApi31(info: _info).paths, isEmpty);
      expect(
        registry
            .toOpenApi31(
              info: _info,
              config: const AuthPluginOpenApiConfig(includeServerOnly: true),
            )
            .paths,
        contains('/auth/internal/rotate'),
      );
    });

    test('emits public policy effects and a sign-in 2FA alternative', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        UsernamePlugin<Object>(),
        CaptchaPlugin<Object>(
          verifier: _AcceptingCaptchaVerifier(),
          config: const AuthCaptchaPluginConfig(maxTokenLength: 8),
        ),
        BreachedPasswordPlugin<Object>(
          lookup: _AllowedBreachedPasswordLookup(),
          config: const AuthBreachedPasswordPluginConfig(maxPasswordLength: 20),
        ),
        TwoFactorPlugin<Object>(
          backend: InMemoryAuthTwoFactorBackend(),
          secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        ),
      ]);

      final spec = registry.toOpenApi31(info: _info);
      final schemas = spec.components!.schemas;
      final registration = spec.paths['/auth/username/register']!.post!;
      final signIn = spec.paths['/auth/username/sign-in']!.post!;
      final change = spec.paths['/auth/username/change']!.post!;
      final remove = spec.paths['/auth/username/remove']!.post!;
      final registrationRequest = schemas['AuthUsernameRegisterRequest']!;
      final registrationProperties =
          registrationRequest['properties']! as Map<String, Object?>;
      final registrationPassword =
          registrationProperties['password']! as Map<String, Object?>;

      expect(
        registrationRequest['required'],
        containsAll(<String>['username', 'password', 'captchaToken']),
      );
      expect(
        registrationProperties['captchaToken'],
        containsPair('maxLength', 8),
      );
      expect(registrationPassword['maxLength'], 20);
      expect(
        registration.extensions[AuthPluginOpenApiGenerator.captchaExtension],
        containsPair('required', true),
      );
      expect(
        registration.extensions[AuthPluginOpenApiGenerator
            .breachedPasswordExtension],
        containsPair('error', authBreachedPasswordRejectedErrorCode),
      );
      expect(
        registration.responses.keys,
        containsAll(<String>['400', '401', '403', '429']),
      );
      expect(signIn.responses, contains('202'));
      expect(change.security, isNotEmpty);
      expect(remove.security, isNotEmpty);
      expect(
        registration.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'atomic',
          'replaySafety': 'singleUse',
          'persistenceReference': <String, Object?>{
            'schemaId': 'username',
            'atomicOperationId': 'username.register',
          },
        },
      );
      expect(
        change.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'atomic',
          'replaySafety': 'idempotent',
          'persistenceReference': <String, Object?>{
            'schemaId': 'username',
            'atomicOperationId': 'username.change',
          },
        },
      );
      expect(
        remove.extensions[AuthPluginOpenApiGenerator
            .operationSemanticsExtension],
        <String, Object?>{
          'effect': 'mutation',
          'persistence': 'durable',
          'atomicity': 'atomic',
          'replaySafety': 'idempotent',
          'persistenceReference': <String, Object?>{
            'schemaId': 'username',
            'atomicOperationId': 'username.remove',
          },
        },
      );
      expect(
        schemas[AuthPluginOpenApiGenerator.twoFactorChallengeSchema],
        containsPair('required', <String>[
          'status',
          'challengeToken',
          'expiresAt',
        ]),
      );
      expect(
        (schemas['AuthUsernameRegisterResponse']!['properties']!
            as Map<String, Object?>)['token'],
        containsPair('type', 'string'),
      );
      expect(
        (schemas['AuthUsernameRegisterResponse']!['required']!
            as List<Object?>),
        isNot(contains('token')),
      );
      expect(
        (registration.responses['429']!.headers!['Retry-After']!
            as Map<String, Object?>)['schema'],
        containsPair('minimum', 1),
      );
      expect(
        registration.extensions[AuthPluginOpenApiGenerator
            .rateLimitOperationExtension],
        <String, Object?>{
          'id': 'username.registration',
          'namespace': 'username',
          'name': 'registration',
        },
      );
      _expectGeneratedClientCompatible(spec);
    });

    test('advertises API-key security for enabled host exchange routes', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        AuthApiKeyPlugin<Object>(
          store: InMemoryAuthApiKeyStore(),
          sessionExchangeEnabled: true,
        ),
      ]);

      final spec = registry.toOpenApi31(
        info: _info,
        config: const AuthPluginOpenApiConfig(
          sessionSecurity: AuthOpenApiSessionSecurity.apiKey,
        ),
      );

      expect(spec.paths, contains('/auth/api-keys/create'));
      expect(spec.paths, contains('/auth/api-keys/exchange'));
      expect(spec.components!.securitySchemes, contains('authApiKey'));
      expect(
        spec.components!.securitySchemes['authApiKey']!.toJson(),
        containsPair('in', 'header'),
      );
      expect(
        spec.paths['/auth/api-keys/exchange']!.post!.security!.any(
          (alternative) => alternative.containsKey('authApiKey'),
        ),
        isTrue,
      );
    });

    test('omits host routes whose owning plugin capability is disabled', () {
      final withoutTwoFactor = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
        AuthApiKeyPlugin<Object>(store: InMemoryAuthApiKeyStore()),
      ]).toOpenApi31(info: _info);
      final withTwoFactor = _registry(<AuthServerPlugin<Object>>[
        AnonymousPlugin<Object>(),
        AuthApiKeyPlugin<Object>(store: InMemoryAuthApiKeyStore()),
        TwoFactorPlugin<Object>(
          backend: InMemoryAuthTwoFactorBackend(),
          secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        ),
      ]).toOpenApi31(info: _info);

      expect(
        withoutTwoFactor.paths,
        isNot(contains('/auth/api-keys/exchange')),
      );
      expect(
        withoutTwoFactor.paths.keys,
        everyElement(isNot(contains('/2fa/'))),
      );
      expect(withTwoFactor.paths, contains('/auth/2fa/status'));
      expect(withTwoFactor.paths, contains('/auth/2fa/challenge/verify'));
      expect(
        withoutTwoFactor.paths['/auth/sign-in/anonymous']!.post!.responses,
        isNot(contains('202')),
      );
      expect(
        withTwoFactor.paths['/auth/sign-in/anonymous']!.post!.responses,
        contains('202'),
      );
    });

    test('policy-only plugins do not create paths or catalogue entries', () {
      final registry = _registry(<AuthServerPlugin<Object>>[
        CaptchaPlugin<Object>(verifier: _AcceptingCaptchaVerifier()),
        BreachedPasswordPlugin<Object>(
          lookup: _AllowedBreachedPasswordLookup(),
        ),
      ]);

      final spec = registry.toOpenApi31(info: _info);

      expect(spec.paths, isEmpty);
      expect(spec.tags, isEmpty);
      expect(spec.toJson(), isNot(contains('paths')));
    });

    test('requires the registry topology to be frozen', () {
      final store = InMemoryAuthStore();
      final registry = AuthServerPluginRegistry<Object>(
        store: store,
        authenticationMethods: AuthAuthenticationMethodService(store: store),
      );

      expect(
        () => registry.toOpenApi31(info: _info),
        throwsA(isA<AuthOpenApiContractException>()),
      );
    });
  });
}

const _info = OpenApiInfo(title: 'Auth API', version: '1.0.0');

AuthServerPluginRegistry<Object> _registry(
  Iterable<AuthServerPlugin<Object>> plugins,
) {
  final store = InMemoryAuthStore();
  final registry = AuthServerPluginRegistry<Object>(
    store: store,
    authenticationMethods: AuthAuthenticationMethodService(store: store),
  );
  for (final plugin in plugins) {
    registry.register(plugin);
  }
  registry.freeze();
  return registry;
}

void _expectGeneratedClientCompatible(OpenApiSpec spec) {
  final json = spec.toJson();
  expect(json['openapi'], '3.1.0');
  final components = json['components']! as Map<String, Object?>;
  final schemas = components['schemas']! as Map<String, Object?>;
  final seenOperationIds = <String>{};
  final paths = json['paths']! as Map<String, Object?>;

  for (final pathEntry in paths.entries) {
    final path = pathEntry.value! as Map<String, Object?>;
    for (final method in <String>['get', 'post']) {
      final value = path[method];
      if (value is! Map<String, Object?>) continue;
      final operationId = value['operationId']! as String;
      expect(operationId, matches(RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$')));
      expect(
        seenOperationIds.add(operationId),
        isTrue,
        reason: 'Duplicate operationId $operationId',
      );
      expect(value['responses'], isA<Map<String, Object?>>());
      final responses = value['responses']! as Map<String, Object?>;
      final success = responses['200']! as Map<String, Object?>;
      _expectSchemaReferencesResolve(success, schemas);
      if (value['requestBody'] case final Map<String, Object?> requestBody) {
        _expectSchemaReferencesResolve(requestBody, schemas);
      }
    }
  }

  expect(OpenApiSpec.fromJson(json).toJson(), json);
}

void _expectSchemaReferencesResolve(
  Map<String, Object?> value,
  Map<String, Object?> schemas,
) {
  final references = <String>[];
  void visit(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (entry.key == r'$ref' && entry.value is String) {
          references.add(entry.value! as String);
        } else {
          visit(entry.value);
        }
      }
    } else if (node is Iterable) {
      for (final child in node) {
        visit(child);
      }
    }
  }

  visit(value);
  expect(references, isNotEmpty);
  for (final reference in references) {
    const prefix = '#/components/schemas/';
    expect(reference, startsWith(prefix));
    expect(schemas, contains(reference.substring(prefix.length)));
  }
}

final class _ContractPlugin
    implements AuthServerPlugin<Object>, AuthEndpointContributor<Object> {
  const _ContractPlugin({
    required this.id,
    required List<_EndpointContract> endpoints,
  }) : _contracts = endpoints;

  @override
  final String id;

  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract.none();
  final List<_EndpointContract> _contracts;

  @override
  void configure(AuthServerPluginContext<Object> context) {}

  @override
  Iterable<AuthEndpointDescriptor<Object>> get endpoints =>
      _contracts.map((contract) => contract.descriptor);
}

final class _EndpointContract {
  const _EndpointContract({
    required this.id,
    required this.method,
    required this.path,
    required this.semantics,
    required this.requestSchema,
    required this.responseSchema,
    this.requestRequired = false,
    this.csrfRequired = false,
    this.serverOnly = false,
    this.pathParameters = const <AuthRouteParameterKey>[],
    this.mount = AuthEndpointMount.auth,
  });

  final String id;
  final AuthOperationMethod method;
  final String path;
  final AuthOperationSemantics semantics;
  final Map<String, Object?> requestSchema;
  final Map<String, Object?> responseSchema;
  final bool requestRequired;
  final bool csrfRequired;
  final bool serverOnly;
  final List<AuthRouteParameterKey> pathParameters;
  final AuthEndpointMount mount;

  AuthEndpointDescriptor<Object> get descriptor =>
      TypedAuthEndpointDescriptor<Object, Map<String, dynamic>, Object?>(
        id: id,
        method: method,
        path: AuthRoutePath(path, parameters: pathParameters),
        mount: mount,
        semantics: semantics,
        requestCodec: AuthOperationCodec<Map<String, dynamic>>(
          decode: (value) => value,
          encode: (value) => value,
          schema: requestSchema,
          required: requestRequired,
        ),
        responseCodec: AuthOperationCodec<Object?>(
          decode: (value) => value,
          encode: (value) => value,
          schema: responseSchema,
        ),
        authentication: AuthOperationAuthentication.none,
        csrfPolicy: csrfRequired
            ? AuthOperationCsrfPolicy.required
            : AuthOperationCsrfPolicy.none,
        serverOnly: serverOnly,
        handler: (invocation, request) => <String, Object?>{},
      );
}

final class _AcceptingCaptchaVerifier implements AuthCaptchaVerifier<Object> {
  @override
  Future<AuthCaptchaVerificationResult> verify(
    AuthCaptchaVerificationRequest<Object> request,
  ) async => const AuthCaptchaVerificationResult.accepted();
}

final class _AllowedBreachedPasswordLookup
    implements AuthBreachedPasswordLookup<Object> {
  @override
  Future<AuthBreachedPasswordCheckResult> check(
    AuthBreachedPasswordCheckRequest<Object> request,
  ) async => const AuthBreachedPasswordCheckResult.allowed();
}

final class _SamlCatalog implements AuthSamlConnectionCatalog {
  final connection = AuthSamlConnection(
    providerId: 'enterprise',
    idpEntityId: 'https://idp.example.test/entity',
    idpSsoUrl: Uri.parse('https://idp.example.test/sso'),
    idpSigningCertificate: 'PINNED CERTIFICATE',
    spEntityId: 'https://sp.example.test/entity',
    assertionConsumerServiceUrl: Uri.parse(
      'https://sp.example.test/auth/sso/saml/acs/enterprise',
    ),
  );

  @override
  AuthSamlConnection? findByProviderId(String providerId) =>
      providerId == connection.providerId ? connection : null;
  @override
  AuthSamlConnection? findByVerifiedDomain(String domain) => null;
  @override
  AuthSamlConnection? findByOrganizationSlug(String slug) => null;
}

final class _SamlVerifier implements AuthSamlAssertionVerifier {
  const _SamlVerifier();
  @override
  AuthSamlSignatureProof verify(AuthSamlVerificationInput input) =>
      AuthSamlSignatureProof(
        signedResponseId: null,
        signedAssertionId: input.assertionId,
        signatureAlgorithm: 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256',
        digestAlgorithm: 'http://www.w3.org/2001/04/xmlenc#sha256',
        canonicalizationAlgorithm: 'http://www.w3.org/2001/10/xml-exc-c14n#',
      );
}

final class _SamlResolver implements AuthSamlIdentityResolver<Object> {
  const _SamlResolver();
  @override
  AuthUser resolveOrProvision(AuthSamlIdentityInput<Object> input) =>
      AuthUser(id: input.identity.stableKey);
}
