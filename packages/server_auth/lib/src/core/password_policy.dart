/// Password acceptance policy for the built-in credentials flow.
///
/// The default follows a length-first policy: passwords must be at least
/// twelve characters and no longer than 1,024 characters. Complexity rules
/// are deliberately opt-in so applications can choose their own policy
/// without forcing predictable composition requirements on users.
class PasswordPolicy {
  const PasswordPolicy({this.minimumLength = 12, this.maximumLength = 1024})
    : assert(minimumLength >= 1),
      assert(maximumLength >= minimumLength);

  /// Minimum password length accepted during registration.
  final int minimumLength;

  /// Maximum password length accepted during registration and authentication.
  ///
  /// This bound also protects the hash verifier from unbounded attacker input.
  final int maximumLength;

  /// Returns a stable validation code for registration, or `null` when valid.
  String? validateRegistration(String password) {
    if (password.length < minimumLength) {
      return 'password_too_short';
    }
    if (password.length > maximumLength) {
      return 'password_too_long';
    }
    return null;
  }

  /// Returns whether [password] is safe to send to the password verifier.
  ///
  /// Authentication deliberately does not enforce the minimum length: older
  /// records may predate the current registration policy and must still be
  /// able to authenticate and rehash. The maximum remains enforced to bound
  /// verifier work.
  bool allowsAuthentication(String password) =>
      password.length <= maximumLength;
}
