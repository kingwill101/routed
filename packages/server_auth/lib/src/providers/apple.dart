import '../core/core.dart';

/// Apple user profile returned by the ID token.
///
/// See [Sign in with Apple REST API](https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api).
class AppleProfile {
  /// Creates a new [AppleProfile] with the given fields.
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

  /// Creates an [AppleProfile] from a JSON map decoded from the Apple ID token.
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

  /// Converts this profile to a JSON-serializable map.
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
  /// Creates a new [AppleName].
  const AppleName({this.firstName, this.lastName});

  /// User's first name.
  final String? firstName;

  /// User's last name.
  final String? lastName;

  /// Creates an [AppleName] from a JSON map.
  factory AppleName.fromJson(Map<String, dynamic> json) {
    return AppleName(
      firstName: json['firstName']?.toString(),
      lastName: json['lastName']?.toString(),
    );
  }

  /// Converts this name to a JSON-serializable map.
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
/// import 'package:server_auth/server_auth.dart';
/// import 'package:server_auth/server_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     store: InMemoryAuthStore(),
///     storeMode: AuthStoreMode.ephemeral,
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
  /// Creates a new [AppleProviderOptions] configuration.
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

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['name', 'email']`.
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
    oidcIssuer: Uri.parse('https://appleid.apple.com'),
    oidcJwksUri: Uri.parse('https://appleid.apple.com/auth/keys'),
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
