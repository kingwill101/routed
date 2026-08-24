import 'package:server_auth/src/core/client.dart';
import 'package:server_auth/src/core/models.dart';

/// Installs captcha-aware credential operations on an [AuthClient].
///
/// Applications only need this client plugin when the server composes a
/// `CaptchaPlugin`. The normal credentials client remains captcha-agnostic.
final class AuthCaptchaClientPlugin
    implements AuthClientPlugin<AuthCaptchaClient> {
  /// Creates the captcha client plugin for [provider].
  const AuthCaptchaClientPlugin({this.provider = 'credentials'});

  /// Provider identifier sent with credential requests.
  final String provider;

  @override
  String get id => 'captcha:$provider';

  @override
  AuthCaptchaClient install(AuthClientPluginContext context) =>
      AuthCaptchaClient(
        AuthClientCore.fromTransport(context.transport),
        provider: provider,
      );
}

/// Typed credential operations protected by one captcha token per request.
final class AuthCaptchaClient {
  /// Creates a captcha-aware client.
  AuthCaptchaClient(this._core, {this.provider = 'credentials'});

  final AuthClientCore _core;

  /// Provider identifier sent with credential requests.
  final String provider;

  /// Signs in with credentials and submits [captchaToken] for verification.
  Future<AuthSession> signIn({
    required String password,
    required String captchaToken,
    String? email,
    String? username,
    Map<String, dynamic>? attributes,
  }) => _core.signInWithCredentials(
    provider: provider,
    email: email,
    username: username,
    password: password,
    attributes: attributes,
    captchaToken: captchaToken,
  );

  /// Registers credentials and submits [captchaToken] for verification.
  Future<AuthSession> register({
    required String password,
    required String captchaToken,
    String? email,
    String? username,
    Map<String, dynamic>? attributes,
  }) => _core.registerWithCredentials(
    provider: provider,
    email: email,
    username: username,
    password: password,
    attributes: attributes,
    captchaToken: captchaToken,
  );
}
