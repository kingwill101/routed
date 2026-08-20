import 'client.dart';
import 'models.dart';

/// Installs captcha-aware credential operations on an [AuthClient].
///
/// Applications only need this client plugin when the server composes a
/// `CaptchaPlugin`. The normal credentials client remains captcha-agnostic.
final class AuthCaptchaClientPlugin
    implements AuthClientPlugin<AuthCaptchaClient> {
  const AuthCaptchaClientPlugin({this.provider = 'credentials'});

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
  AuthCaptchaClient(this._core, {this.provider = 'credentials'});

  final AuthClientCore _core;
  final String provider;

  Future<AuthSession> signIn({
    String? email,
    String? username,
    required String password,
    required String captchaToken,
    Map<String, dynamic>? attributes,
  }) => _core.signInWithCredentials(
    provider: provider,
    email: email,
    username: username,
    password: password,
    attributes: attributes,
    captchaToken: captchaToken,
  );

  Future<AuthSession> register({
    String? email,
    String? username,
    required String password,
    required String captchaToken,
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
