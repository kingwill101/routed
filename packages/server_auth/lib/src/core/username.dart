import 'authentication_methods.dart';
import 'account_policy.dart';
import 'exceptions.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'plugin.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'tokens.dart' show secureRandomToken;
import 'two_factor.dart';
import 'store.dart';
import 'users.dart';
import 'username_store.dart';

const String authUsernamePluginId = 'username';
const String authUsernameAuthenticationMethod = 'username_password';

const AuthRateLimitOperation authUsernameRegistrationRateLimitOperation =
    AuthRateLimitOperation(authUsernamePluginId, 'registration');
const AuthRateLimitOperation authUsernameSignInRateLimitOperation =
    AuthRateLimitOperation(authUsernamePluginId, 'sign_in');
const AuthRateLimitOperation authUsernameChangeRateLimitOperation =
    AuthRateLimitOperation(authUsernamePluginId, 'change');
const AuthRateLimitOperation authUsernameRemovalRateLimitOperation =
    AuthRateLimitOperation(authUsernamePluginId, 'remove');

enum AuthUsernameCaseCanonicalization { lowercase, preserve }

enum AuthUsernameIdentifierKind { username, email }

/// One unambiguous, canonical login identifier.
final class AuthUsernameIdentifier {
  const AuthUsernameIdentifier({required this.kind, required this.value});

  final AuthUsernameIdentifierKind kind;
  final String value;
}

/// Strict policy for username canonicalization and email intent resolution.
///
/// Any input containing `@` is treated exclusively as email intent. An invalid
/// email therefore never falls back to the username namespace. Usernames can
/// never contain `@`, even when a custom allowed-character expression would
/// otherwise accept it.
final class AuthUsernameIdentifierPolicy {
  AuthUsernameIdentifierPolicy({
    this.caseCanonicalization = AuthUsernameCaseCanonicalization.lowercase,
    this.minimumLength = 3,
    this.maximumLength = 32,
    this.allowedCharactersPattern = r'[a-z0-9._-]',
    this.requireDottedEmailDomain = true,
  }) : _allowedCharacters = RegExp(
         '^(?:$allowedCharactersPattern)+\$',
         unicode: true,
       ) {
    if (minimumLength <= 0 || maximumLength < minimumLength) {
      throw ArgumentError('Invalid username length range');
    }
    if (maximumLength > 256) {
      throw ArgumentError.value(
        maximumLength,
        'maximumLength',
        'must not exceed 256',
      );
    }
    if (allowedCharactersPattern.isEmpty) {
      throw ArgumentError.value(
        allowedCharactersPattern,
        'allowedCharactersPattern',
        'must not be empty',
      );
    }
  }

  final AuthUsernameCaseCanonicalization caseCanonicalization;
  final int minimumLength;
  final int maximumLength;
  final String allowedCharactersPattern;
  final bool requireDottedEmailDomain;
  final RegExp _allowedCharacters;

  String? normalizeUsername(String input) {
    var candidate = input.trim();
    if (candidate.contains('@')) return null;
    if (caseCanonicalization == AuthUsernameCaseCanonicalization.lowercase) {
      candidate = candidate.toLowerCase();
    }
    final length = candidate.runes.length;
    if (length < minimumLength || length > maximumLength) return null;
    return _allowedCharacters.hasMatch(candidate) ? candidate : null;
  }

  String? normalizeEmail(String input) {
    final candidate = normalizeAuthEmail(input);
    if (candidate.length > 254 || candidate.runes.any(_isEmailWhitespace)) {
      return null;
    }
    final separator = candidate.indexOf('@');
    if (separator <= 0 || separator != candidate.lastIndexOf('@')) return null;
    final local = candidate.substring(0, separator);
    final domain = candidate.substring(separator + 1);
    if (local.length > 64 ||
        local.startsWith('.') ||
        local.endsWith('.') ||
        local.contains('..') ||
        !_emailLocal.hasMatch(local) ||
        !_validEmailDomain(domain, requireDot: requireDottedEmailDomain)) {
      return null;
    }
    return candidate;
  }

  AuthUsernameIdentifier? resolve(String input) {
    if (input.contains('@')) {
      final email = normalizeEmail(input);
      return email == null
          ? null
          : AuthUsernameIdentifier(
              kind: AuthUsernameIdentifierKind.email,
              value: email,
            );
    }
    final username = normalizeUsername(input);
    return username == null
        ? null
        : AuthUsernameIdentifier(
            kind: AuthUsernameIdentifierKind.username,
            value: username,
          );
  }

  static final RegExp _emailLocal = RegExp(r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$");

  static bool _isEmailWhitespace(int rune) =>
      rune <= 0x20 || rune == 0x7f || rune == 0xa0;

  static bool _validEmailDomain(String domain, {required bool requireDot}) {
    if (domain.isEmpty || domain.length > 253) return false;
    final labels = domain.split('.');
    if (requireDot && labels.length < 2) return false;
    for (final label in labels) {
      if (label.isEmpty ||
          label.length > 63 ||
          label.startsWith('-') ||
          label.endsWith('-') ||
          !RegExp(r'^[a-z0-9-]+$').hasMatch(label)) {
        return false;
      }
    }
    return true;
  }
}

final class AuthUsernameRegistrationRequest {
  const AuthUsernameRegistrationRequest({
    required this.username,
    required this.password,
    this.email,
    this.captchaToken,
  });

  final String username;
  final String? email;
  final String password;
  final String? captchaToken;

  factory AuthUsernameRegistrationRequest.fromJson(Map<String, dynamic> json) =>
      AuthUsernameRegistrationRequest(
        username: _requiredString(json, 'username'),
        email: _optionalString(json, 'email', maximumLength: 254),
        password: _requiredString(json, 'password'),
        captchaToken: _optionalString(
          json,
          'captchaToken',
          maximumLength: 16384,
        ),
      );
}

final class AuthUsernameSignInRequest {
  const AuthUsernameSignInRequest({
    required this.identifier,
    required this.password,
    this.captchaToken,
  });

  final String identifier;
  final String password;
  final String? captchaToken;

  factory AuthUsernameSignInRequest.fromJson(Map<String, dynamic> json) =>
      AuthUsernameSignInRequest(
        identifier: _requiredString(json, 'identifier'),
        password: _requiredString(json, 'password'),
        captchaToken: _optionalString(
          json,
          'captchaToken',
          maximumLength: 16384,
        ),
      );
}

final class AuthUsernameChangeRequest {
  const AuthUsernameChangeRequest({required this.username});

  final String username;

  factory AuthUsernameChangeRequest.fromJson(Map<String, dynamic> json) =>
      AuthUsernameChangeRequest(username: _requiredString(json, 'username'));
}

final class AuthUsernameChangeResult {
  const AuthUsernameChangeResult({
    required this.username,
    required this.user,
    required this.changed,
  });

  final String username;
  final AuthUser user;
  final bool changed;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': changed ? 'username_changed' : 'username_unchanged',
    'username': username,
    'user': user.toJson(),
  };
}

final class AuthUsernameAuthenticationResult {
  const AuthUsernameAuthenticationResult({
    required this.username,
    required this.user,
  });

  final String username;
  final AuthUser user;
}

final class AuthUsernameAuthenticationResponse {
  const AuthUsernameAuthenticationResponse({
    required this.username,
    required this.user,
  });

  final String username;
  final AuthUser user;

  AuthEndpointAuthenticationIntent toAuthenticationIntent(
    AuthProvider provider, {
    required String authenticationMethod,
  }) => AuthEndpointAuthenticationIntent(
    user: user,
    authenticationMethod: authenticationMethod,
    provider: provider,
    metadata: <String, dynamic>{
      'status': 'authenticated',
      'username': username,
    },
  );
}

/// Opt-in username-first password authentication.
final class UsernamePlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthServerPluginTopologyAware<TContext>,
        AuthEndpointContributor<TContext>,
        AuthClientOperationContributor,
        AuthPersistenceContributor,
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding,
        AuthRateLimitContributor {
  UsernamePlugin({
    AuthUsernameIdentifierPolicy? identifierPolicy,
    this.authenticationMethod = authUsernameAuthenticationMethod,
  }) : identifierPolicy = identifierPolicy ?? AuthUsernameIdentifierPolicy();

  final AuthUsernameIdentifierPolicy identifierPolicy;
  final String authenticationMethod;
  final CredentialsProvider _provider = CredentialsProvider(
    id: authUsernamePluginId,
    name: 'Username',
  );

  late AuthUsernameStore _store;
  late AuthCredentialStore _credentialStore;
  late AuthUserStore _users;
  AuthAccountStateStore? _accountStates;
  late AuthAuthenticationMethodService _authenticationMethods;
  late PasswordHasher _passwordHasher;
  late PasswordPolicy _passwordPolicy;
  final List<AuthCredentialPolicyContributor<TContext>> _credentialPolicies =
      <AuthCredentialPolicyContributor<TContext>>[];
  final List<AuthPasswordPolicyContributor<TContext>> _passwordPolicies =
      <AuthPasswordPolicyContributor<TContext>>[];
  final List<AuthAuthenticationPolicyContributor<TContext>>
  _authenticationPolicies = <AuthAuthenticationPolicyContributor<TContext>>[];
  TwoFactorPlugin<TContext>? _twoFactor;
  bool _configured = false;

  @override
  String get id => authUsernamePluginId;

  @override
  String get authenticationMethodNamespace => authUsernamePluginId;

  @override
  Object get authenticationMethodStore => _store;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.username,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async {
    _ensureConfigured();
    final credential = await _store.findUsernameForUser(userId);
    final user = await _users.findById(userId);
    final state = await _accountStates?.find(userId);
    return AuthAuthenticationMethodSnapshot.complete([
      if (credential?.enabled == true &&
          user != null &&
          !authUserIsDisabled(user) &&
          state?.disabled != true &&
          state?.isLocked() != true)
        AuthAuthenticationMethod.username(credential!.id),
    ]);
  }

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    final store = context.store;
    if (store is! AuthUsernameStore) {
      throw StateError(
        'UsernamePlugin requires root AuthUsernameStore atomicity.',
      );
    }
    if (authenticationMethod.trim().isEmpty) {
      throw ArgumentError.value(
        authenticationMethod,
        'authenticationMethod',
        'must not be empty',
      );
    }
    _store = store as AuthUsernameStore;
    _credentialStore = context.store.credentials;
    _users = context.store.users;
    _accountStates = store is AuthAccountStateStore
        ? store as AuthAccountStateStore
        : null;
    _authenticationMethods =
        context.authenticationMethods ??
        (throw StateError(
          'UsernamePlugin requires an authentication-method coordinator.',
        ));
    _passwordHasher = context.passwordHasher ?? Argon2idPasswordHasher();
    _passwordPolicy = context.passwordPolicy;
    _configured = true;
  }

  @override
  void composePluginTopology(Iterable<AuthServerPlugin<TContext>> plugins) {
    _credentialPolicies
      ..clear()
      ..addAll(
        plugins
            .where((plugin) => !identical(plugin, this))
            .whereType<AuthCredentialPolicyContributor<TContext>>(),
      );
    _passwordPolicies
      ..clear()
      ..addAll(
        plugins
            .where((plugin) => !identical(plugin, this))
            .whereType<AuthPasswordPolicyContributor<TContext>>(),
      );
    _authenticationPolicies
      ..clear()
      ..addAll(
        plugins
            .where((plugin) => !identical(plugin, this))
            .whereType<AuthAuthenticationPolicyContributor<TContext>>(),
      );
    _twoFactor = plugins.whereType<TwoFactorPlugin<TContext>>().firstOrNull;
  }

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      <AuthEndpointDescriptor<TContext>>[
        TypedAuthEndpointDescriptor<
          TContext,
          AuthUsernameRegistrationRequest,
          AuthUsernameAuthenticationResponse
        >(
          id: 'username.register',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/username/register'),
          semantics: const AuthOperationSemantics.mutation(
            persistence: AuthMutationPersistence.durable(
              atomicity: AuthMutationAtomicity.atomic,
              reference: AuthPersistenceOperationReference(
                schemaId: authUsernamePluginId,
                atomicOperationId: 'username.register',
              ),
            ),
            replaySafety: AuthMutationReplaySafety.singleUse,
          ),
          requestCodec: _registrationRequestCodec,
          responseCodec: _responseCodec,
          authentication: AuthOperationAuthentication.none,
          originPolicy: AuthOperationOriginPolicy.browser,
          rateLimitOperation: authUsernameRegistrationRateLimitOperation,
          rateLimitIdentifier: (request) =>
              identifierPolicy.normalizeUsername(request.username),
          handler: (invocation, request) async {
            final result = await register(
              context: invocation.context,
              request: request,
              sessionControl: invocation.sessionControl,
            );
            return AuthUsernameAuthenticationResponse(
              username: result.username,
              user: result.user,
            );
          },
        ),
        TypedAuthEndpointDescriptor<
          TContext,
          AuthUsernameSignInRequest,
          AuthUsernameAuthenticationResponse
        >(
          id: 'username.signIn',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/username/sign-in'),
          semantics: const AuthOperationSemantics.mutation(
            persistence: AuthMutationPersistence.session(),
            replaySafety: AuthMutationReplaySafety.repeatable,
          ),
          requestCodec: _signInRequestCodec,
          responseCodec: _responseCodec,
          authentication: AuthOperationAuthentication.none,
          originPolicy: AuthOperationOriginPolicy.browser,
          rateLimitOperation: authUsernameSignInRateLimitOperation,
          rateLimitIdentifier: (request) =>
              identifierPolicy.resolve(request.identifier)?.value,
          handler: (invocation, request) async {
            final result = await signIn(
              context: invocation.context,
              request: request,
              sessionControl: invocation.sessionControl,
            );
            return AuthUsernameAuthenticationResponse(
              username: result.username,
              user: result.user,
            );
          },
        ),
        TypedAuthEndpointDescriptor<
          TContext,
          AuthUsernameChangeRequest,
          AuthUsernameChangeResult
        >(
          id: 'username.change',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/username/change'),
          semantics: const AuthOperationSemantics.mutation(
            persistence: AuthMutationPersistence.durable(
              atomicity: AuthMutationAtomicity.atomic,
              reference: AuthPersistenceOperationReference(
                schemaId: authUsernamePluginId,
                atomicOperationId: 'username.change',
              ),
            ),
            replaySafety: AuthMutationReplaySafety.idempotent,
          ),
          requestCodec: _changeRequestCodec,
          responseCodec: _changeResponseCodec,
          authentication: AuthOperationAuthentication.session,
          originPolicy: AuthOperationOriginPolicy.browser,
          csrfPolicy: AuthOperationCsrfPolicy.required,
          rateLimitOperation: authUsernameChangeRateLimitOperation,
          handler: (invocation, request) => changeUsername(
            userId: _invocationUserId(invocation),
            request: request,
          ),
        ),
        TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
          id: 'username.remove',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/username/remove'),
          semantics: const AuthOperationSemantics.mutation(
            persistence: AuthMutationPersistence.durable(
              atomicity: AuthMutationAtomicity.atomic,
              reference: AuthPersistenceOperationReference(
                schemaId: authUsernamePluginId,
                atomicOperationId: 'username.remove',
              ),
            ),
            replaySafety: AuthMutationReplaySafety.idempotent,
          ),
          requestCodec: _emptyRequestCodec,
          responseCodec: _objectResponseCodec,
          authentication: AuthOperationAuthentication.session,
          originPolicy: AuthOperationOriginPolicy.browser,
          csrfPolicy: AuthOperationCsrfPolicy.required,
          rateLimitOperation: authUsernameRemovalRateLimitOperation,
          handler: (invocation, _) async {
            await removeUsername(userId: _invocationUserId(invocation));
            return const <String, dynamic>{'status': 'username_removed'};
          },
        ),
      ];

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      mount: endpoint.mount,
      serverOnly: endpoint.serverOnly,
    ),
  );

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations =>
      const <AuthRateLimitOperation>[
        authUsernameRegistrationRateLimitOperation,
        authUsernameSignInRateLimitOperation,
        authUsernameChangeRateLimitOperation,
        authUsernameRemovalRateLimitOperation,
      ];

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: authUsernamePluginId,
      entities: <AuthEntityDescriptor>[
        AuthEntityDescriptor(
          id: 'auth_username',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'credentialId', kind: 'id'),
            AuthFieldDescriptor(name: 'userId', kind: 'id'),
            AuthFieldDescriptor(name: 'identifier', kind: 'string'),
            AuthFieldDescriptor(name: 'passwordHash', kind: 'digest'),
            AuthFieldDescriptor(name: 'enabled', kind: 'boolean'),
          ],
          relationships: <AuthRelationshipDescriptor>[
            AuthRelationshipDescriptor(
              field: 'userId',
              targetEntity: 'user',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: <List<String>>[
            <String>['credentialId'],
            <String>['identifier'],
          ],
          indexes: <List<String>>[
            <String>['userId'],
          ],
        ),
      ],
      atomicOperations: <AuthAtomicOperationDescriptor>[
        AuthAtomicOperationDescriptor(
          id: 'username.register',
          description:
              'Reserve the normalized username and optional email with the user and credential.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'username.change',
          description:
              'Replace the username reservation, credential identifier, and user projection.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'username.remove',
          description:
              'Remove the username credential and projection only when another method remains.',
        ),
      ],
    ),
  ];

  Future<AuthUsernameAuthenticationResult> register({
    required TContext context,
    required AuthUsernameRegistrationRequest request,
    AuthServerPluginSessionControl? sessionControl,
  }) async {
    _ensureConfigured();
    final username = identifierPolicy.normalizeUsername(request.username);
    final email = request.email == null
        ? null
        : identifierPolicy.normalizeEmail(request.email!);
    if (username == null || (request.email != null && email == null)) {
      throw AuthFlowException('registration_failed');
    }
    await _enforceCredentialPolicies(
      context,
      AuthCredentialPolicyOperation.registration,
      username,
      request.captchaToken,
    );
    for (final policy in _passwordPolicies) {
      await policy.enforcePasswordPolicy(
        AuthPasswordPolicyRequest<TContext>(
          context: context,
          operation: AuthPasswordPolicyOperation.registration,
          password: request.password,
        ),
      );
    }
    if (_passwordPolicy.validateRegistration(request.password) != null) {
      throw AuthFlowException('registration_failed');
    }

    final now = DateTime.now().toUtc();
    final user = AuthUser(
      id: secureRandomToken(length: 24),
      email: email,
      name: username,
      attributes: <String, dynamic>{'username': username},
    );
    final credential = AuthPasswordCredential(
      id: secureRandomToken(length: 24),
      userId: user.id,
      identifier: username,
      passwordHash: _passwordHasher.hash(request.password),
      createdAt: now,
      updatedAt: now,
    );
    AuthUsernameMutationResult persisted;
    try {
      persisted = await _store.registerUsername(
        AuthUsernameRegistrationCommand(user: user, credential: credential),
      );
    } catch (_) {
      throw AuthFlowException('registration_failed');
    }
    final created = persisted.user;
    if (persisted.status != AuthUsernameMutationStatus.created ||
        created == null ||
        persisted.credential?.id != credential.id) {
      throw AuthFlowException('registration_failed');
    }
    await _enforceAuthenticationPoliciesIfPortable(
      context,
      created,
      sessionControl,
    );
    return AuthUsernameAuthenticationResult(username: username, user: created);
  }

  Future<AuthUsernameAuthenticationResult> signIn({
    required TContext context,
    required AuthUsernameSignInRequest request,
    AuthServerPluginSessionControl? sessionControl,
  }) async {
    _ensureConfigured();
    final identifier = identifierPolicy.resolve(request.identifier);
    if (identifier == null ||
        request.password.isEmpty ||
        !_passwordPolicy.allowsAuthentication(request.password)) {
      throw AuthFlowException('invalid_credentials');
    }
    await _enforceCredentialPolicies(
      context,
      AuthCredentialPolicyOperation.signIn,
      identifier.value,
      request.captchaToken,
    );

    AuthPasswordCredential? credential;
    try {
      if (identifier.kind == AuthUsernameIdentifierKind.username) {
        credential = await _store.findByUsername(identifier.value);
      } else {
        final user = await _users.findByEmail(identifier.value);
        credential = user == null
            ? null
            : await _store.findUsernameForUser(user.id);
      }
      if (credential == null || !credential.enabled) {
        throw AuthFlowException('invalid_credentials');
      }
      final verification = _passwordHasher.verify(
        request.password,
        credential.passwordHash,
      );
      if (!verification.matches) {
        throw AuthFlowException('invalid_credentials');
      }
      if (verification.needsRehash) {
        await _credentialStore.update(
          credential.copyWith(
            passwordHash: _passwordHasher.hash(request.password),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      }
    } on AuthFlowException {
      rethrow;
    } catch (_) {
      throw AuthFlowException('invalid_credentials');
    }
    final user = await _users.findById(credential.userId);
    final state = user == null ? null : await _accountStates?.find(user.id);
    if (user == null ||
        authUserIsDisabled(user) ||
        state?.disabled == true ||
        state?.isLocked() == true) {
      throw AuthFlowException('invalid_credentials');
    }
    final username = user.attributes['username'];
    if (username is! String || username != credential.identifier) {
      throw AuthFlowException('invalid_credentials');
    }
    await _enforceAuthenticationPoliciesIfPortable(
      context,
      user,
      sessionControl,
    );
    final challenge = await _twoFactor?.beginSignInChallenge(
      user.id,
      user: user,
      credentials: AuthCredentials(username: credential.identifier),
    );
    if (challenge != null) {
      throw AuthTwoFactorRequiredException(challenge: challenge);
    }
    return AuthUsernameAuthenticationResult(
      username: credential.identifier,
      user: user,
    );
  }

  Future<AuthUsernameChangeResult> changeUsername({
    required String userId,
    required AuthUsernameChangeRequest request,
    DateTime? now,
  }) async {
    _ensureConfigured();
    final username = identifierPolicy.normalizeUsername(request.username);
    if (username == null) throw AuthFlowException('username_change_failed');
    final user = await _availableUser(
      userId,
      failureCode: 'username_change_failed',
    );
    final credential = await _store.findUsernameForUser(user.id);
    if (credential == null || !credential.enabled) {
      throw AuthFlowException('username_change_failed');
    }
    AuthUsernameMutationResult result;
    try {
      result = await _store.changeUsername(
        AuthUsernameChangeCommand(
          userId: user.id,
          credentialId: credential.id,
          expectedUsername: credential.identifier,
          username: username,
          updatedAt: (now ?? DateTime.now()).toUtc(),
        ),
      );
    } catch (_) {
      throw AuthFlowException('username_change_failed');
    }
    final updated = result.user;
    if (!result.succeeded || updated == null) {
      throw AuthFlowException('username_change_failed');
    }
    return AuthUsernameChangeResult(
      username: username,
      user: updated,
      changed: result.status == AuthUsernameMutationStatus.changed,
    );
  }

  Future<void> removeUsername({required String userId}) async {
    _ensureConfigured();
    final user = await _availableUser(
      userId,
      failureCode: 'username_removal_failed',
    );
    final credential = await _store.findUsernameForUser(user.id);
    if (credential == null) return;
    AuthAuthenticationMethodMutationResult result;
    try {
      result = await _store.removeUsernameIfSafe(
        AuthUsernameRemovalCommand(
          userId: user.id,
          credentialId: credential.id,
          loadInventory: () => _authenticationMethods.snapshotForUser(user.id),
        ),
      );
    } catch (_) {
      throw AuthFlowException('username_removal_failed');
    }
    switch (result) {
      case AuthAuthenticationMethodMutationResult.mutated:
      case AuthAuthenticationMethodMutationResult.notFound:
        return;
      case AuthAuthenticationMethodMutationResult.lastAuthenticationMethod:
        throw AuthFlowException('last_authentication_method');
      case AuthAuthenticationMethodMutationResult.atomicityUnavailable:
        throw AuthFlowException('authentication_method_mutation_unavailable');
    }
  }

  Future<AuthUser> _availableUser(
    String userId, {
    required String failureCode,
  }) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) throw AuthFlowException(failureCode);
    final user = await _users.findById(normalized);
    final state = await _accountStates?.find(normalized);
    if (user == null ||
        authUserIsDisabled(user) ||
        state?.disabled == true ||
        state?.isLocked() == true) {
      throw AuthFlowException(failureCode);
    }
    return user;
  }

  String _invocationUserId(AuthOperationInvocation<TContext> invocation) {
    final user = invocation.user;
    if (user == null) throw AuthFlowException('unauthorized');
    return user.id;
  }

  Future<void> _enforceCredentialPolicies(
    TContext context,
    AuthCredentialPolicyOperation operation,
    String identifier,
    String? captchaToken,
  ) async {
    for (final policy in _credentialPolicies) {
      await policy.enforceCredentialPolicy(
        AuthCredentialPolicyRequest<TContext>(
          context: context,
          provider: _provider,
          operation: operation,
          identifier: identifier,
          verificationToken: captchaToken,
        ),
      );
    }
  }

  Future<void> _enforceAuthenticationPoliciesIfPortable(
    TContext context,
    AuthUser user,
    AuthServerPluginSessionControl? sessionControl,
  ) async {
    if (sessionControl != null) return;
    for (final policy in _authenticationPolicies) {
      await policy.enforceAuthenticationPolicy(
        AuthAuthenticationPolicyRequest<TContext>(
          context: context,
          user: user,
          phase: AuthAuthenticationPolicyPhase.beforeSessionIssue,
        ),
      );
    }
  }

  void _ensureConfigured() {
    if (!_configured) {
      throw StateError('UsernamePlugin must be configured by AuthRuntime.');
    }
  }

  static final AuthOperationCodec<AuthUsernameRegistrationRequest>
  _registrationRequestCodec = AuthOperationCodec(
    decode: AuthUsernameRegistrationRequest.fromJson,
    encode: (_) => throw UnsupportedError('Request-only codec'),
    required: true,
    schema: _registrationRequestSchema,
  );

  static final AuthOperationCodec<AuthUsernameSignInRequest>
  _signInRequestCodec = AuthOperationCodec(
    decode: AuthUsernameSignInRequest.fromJson,
    encode: (_) => throw UnsupportedError('Request-only codec'),
    required: true,
    schema: _signInRequestSchema,
  );

  static final AuthOperationCodec<AuthUsernameChangeRequest>
  _changeRequestCodec = AuthOperationCodec(
    decode: AuthUsernameChangeRequest.fromJson,
    encode: (_) => throw UnsupportedError('Request-only codec'),
    required: true,
    schema: _changeRequestSchema,
  );

  static final AuthOperationCodec<AuthUsernameChangeResult>
  _changeResponseCodec = AuthOperationCodec(
    decode: (_) => throw UnsupportedError('Response-only codec'),
    encode: (response) => response.toJson(),
    schema: _changeResponseSchema,
  );

  static final AuthOperationCodec<Map<String, dynamic>> _emptyRequestCodec =
      AuthOperationCodec(
        decode: (_) => const <String, dynamic>{},
        encode: (value) => value,
        schema: const <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
        },
      );

  static final AuthOperationCodec<Object?> _objectResponseCodec =
      AuthOperationCodec(
        decode: (value) => value,
        encode: (value) => value,
        schema: const <String, Object?>{
          'type': 'object',
          'required': <String>['status'],
          'properties': <String, Object?>{
            'status': <String, Object?>{'const': 'username_removed'},
          },
        },
      );

  AuthOperationCodec<AuthUsernameAuthenticationResponse> get _responseCodec =>
      AuthOperationCodec(
        decode: (_) => throw UnsupportedError('Response-only codec'),
        encode: (response) => response.toAuthenticationIntent(
          _provider,
          authenticationMethod: authenticationMethod,
        ),
        schema: _authenticationResponseSchema,
      );
}

const Map<String, Object?> _registrationRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['username', 'password'],
  'properties': <String, Object?>{
    'username': <String, Object?>{'type': 'string', 'maxLength': 256},
    'email': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'email',
      'maxLength': 254,
    },
    'password': <String, Object?>{
      'type': 'string',
      'format': 'password',
      'writeOnly': true,
    },
    'captchaToken': <String, Object?>{
      'type': <String>['string', 'null'],
      'writeOnly': true,
      'maxLength': 16384,
    },
  },
};

const Map<String, Object?> _signInRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['identifier', 'password'],
  'properties': <String, Object?>{
    'identifier': <String, Object?>{'type': 'string', 'maxLength': 254},
    'password': <String, Object?>{
      'type': 'string',
      'format': 'password',
      'writeOnly': true,
    },
    'captchaToken': <String, Object?>{
      'type': <String>['string', 'null'],
      'writeOnly': true,
      'maxLength': 16384,
    },
  },
};

const Map<String, Object?> _changeRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['username'],
  'properties': <String, Object?>{
    'username': <String, Object?>{'type': 'string', 'maxLength': 256},
  },
};

const Map<String, Object?> _changeResponseSchema = <String, Object?>{
  'type': 'object',
  'required': <String>['status', 'username', 'user'],
  'properties': <String, Object?>{
    'status': <String, Object?>{
      'enum': <String>['username_changed', 'username_unchanged'],
    },
    'username': <String, Object?>{'type': 'string'},
    'user': <String, Object?>{'type': 'object'},
  },
};

const Map<String, Object?> _authenticationResponseSchema = <String, Object?>{
  'type': 'object',
  'required': <String>['status', 'username', 'user'],
  'properties': <String, Object?>{
    'status': <String, Object?>{'const': 'authenticated'},
    'username': <String, Object?>{'type': 'string'},
    'user': <String, Object?>{'type': 'object'},
    'expires': <String, Object?>{
      'type': <String>['string', 'null'],
      'format': 'date-time',
    },
    'strategy': <String, Object?>{'type': 'string'},
    'token': <String, Object?>{'type': 'string'},
  },
};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 16384) {
    throw AuthFlowException('invalid_request');
  }
  return value;
}

String? _optionalString(
  Map<String, dynamic> json,
  String key, {
  required int maximumLength,
}) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.length > maximumLength) {
    throw AuthFlowException('invalid_request');
  }
  return value;
}
