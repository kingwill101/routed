import 'package:routed/routed.dart';

/// Apple user profile returned by the ID token.
///
/// See [Sign in with Apple REST API](https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api).
class AppleProfile {
  const AppleProfile({
    required this.sub,
    this.email,
    this.emailVerified,
    this.isPrivateEmail,
    this.name,
  });

  /// Unique identifier for the user.
  final String sub;

  /// User's email address (may be private relay email).
  final String? email;

  /// Whether the email has been verified.
  final bool? emailVerified;

  /// Whether the email is a private relay address.
  final bool? isPrivateEmail;

  /// User's name (only provided on first sign-in).
  final AppleName? name;

  factory AppleProfile.fromJson(Map<String, dynamic> json) {
    AppleName? name;
    if (json['name'] is Map<String, dynamic>) {
      name = AppleName.fromJson(json['name'] as Map<String, dynamic>);
    }
    return AppleProfile(
      sub: json['sub']?.toString() ?? '',
      email: json['email']?.toString(),
      emailVerified:
          json['email_verified'] == true || json['email_verified'] == 'true',
      isPrivateEmail:
          json['is_private_email'] == true ||
          json['is_private_email'] == 'true',
      name: name,
    );
  }

  Map<String, dynamic> toJson() => {
    'sub': sub,
    'email': email,
    'email_verified': emailVerified,
    'is_private_email': isPrivateEmail,
    'name': name?.toJson(),
  };

  /// Returns the full name from the Apple profile.
  String? get fullName {
    if (name == null) return null;
    final parts = <String>[];
    if (name!.firstName != null) parts.add(name!.firstName!);
    if (name!.lastName != null) parts.add(name!.lastName!);
    return parts.isEmpty ? null : parts.join(' ');
  }
}

/// Apple user name structure.
class AppleName {
  const AppleName({this.firstName, this.lastName});

  final String? firstName;
  final String? lastName;

  factory AppleName.fromJson(Map<String, dynamic> json) {
    return AppleName(
      firstName: json['firstName']?.toString(),
      lastName: json['lastName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
  };
}

/// Configuration for the Apple OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/apple
/// ```
///
/// ### Usage
/// ```dart
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     providers: [
///       appleProvider(
///         AppleProviderOptions(
///           clientId: env('APPLE_CLIENT_ID'), // Service ID
///           clientSecret: env('APPLE_CLIENT_SECRET'), // Generated JWT
///           redirectUri: 'https://example.com/auth/callback/apple',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OpenID Connect.
/// - `clientId` is your Services ID (not Bundle ID).
/// - `clientSecret` is a JWT signed with your private key.
/// - User name is only returned on first sign-in, you must store it.
/// - Apple may return a private relay email address.
class AppleProviderOptions {
  const AppleProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['name', 'email'],
  });

  /// Services ID (not Bundle ID).
  final String clientId;

  /// JWT signed with your Apple private key.
  final String clientSecret;

  final String redirectUri;
  final List<String> scopes;
}

/// Apple Sign In OAuth provider.
///
/// Based on Apple's Sign in with Apple documentation.
///
/// ### Resources
/// - https://developer.apple.com/sign-in-with-apple/get-started/
/// - https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api
///
/// ### Example
/// ```dart
/// final provider = appleProvider(
///   AppleProviderOptions(
///     clientId: 'your.service.id',
///     clientSecret: 'generated-jwt',
///     redirectUri: 'https://example.com/auth/callback/apple',
///   ),
/// );
/// ```
OAuthProvider<AppleProfile> appleProvider(AppleProviderOptions options) {
  return OAuthProvider<AppleProfile>(
    id: 'apple',
    name: 'Apple',
    type: AuthProviderType.oidc,
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse(
      'https://appleid.apple.com/auth/authorize',
    ),
    tokenEndpoint: Uri.parse('https://appleid.apple.com/auth/token'),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    authorizationParams: {'response_mode': 'form_post'},
    useBasicAuth: false,
    profileParser: AppleProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.sub,
        name: profile.fullName,
        email: profile.email,
        image: null, // Apple doesn't provide profile pictures
        attributes: profile.toJson(),
      );
    },
  );
}

const List<String> _defaultAppleScopes = ['name', 'email'];

AuthProviderRegistration _appleRegistration() {
  return AuthProviderRegistration(
    id: 'apple',
    schema: ConfigSchema.object(
      description: 'Apple Sign In OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Apple provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Apple Services ID.',
          defaultValue: "{{ env.APPLE_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Apple client secret (JWT).',
          defaultValue: "{{ env.APPLE_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Apple callbacks.',
          defaultValue: "{{ env.APPLE_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Apple.',
          items: ConfigSchema.string(),
          defaultValue: _defaultAppleScopes,
        ),
      },
    ),
    builder: _buildAppleProvider,
  );
}

AuthProvider? _buildAppleProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.apple.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.apple.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.apple.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.apple.redirect_uri',
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.apple.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultAppleScopes;

  return appleProvider(
    AppleProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultAppleScopes : scopes,
    ),
  );
}

String _requireString(Object? value, String context) {
  final resolved = parseStringLike(
    value,
    context: context,
    allowEmpty: true,
    throwOnInvalid: true,
  );
  if (resolved == null || resolved.trim().isEmpty) {
    throw ProviderConfigException('$context is required');
  }
  return resolved.trim();
}

/// Register the Apple OAuth provider with the registry.
void registerAppleAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_appleRegistration(), overrideExisting: overrideExisting);
}
