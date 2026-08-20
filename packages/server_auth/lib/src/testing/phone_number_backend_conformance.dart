import 'dart:async';

import '../core/models.dart';
import '../core/phone_number_store.dart';
import '../core/store.dart';

typedef AuthPhoneNumberBackendConformanceFactory =
    FutureOr<AuthPhoneNumberBackendConformanceFixture> Function();

enum AuthPhoneNumberBackendConformanceFaultPoint { issue, verify }

abstract interface class AuthPhoneNumberBackendConformanceFaultController {
  void failNext(AuthPhoneNumberBackendConformanceFaultPoint point);
}

final class AuthPhoneNumberBackendConformanceFixture {
  const AuthPhoneNumberBackendConformanceFixture({
    required this.store,
    required this.backend,
    required this.faults,
    required this.hardDeleteUser,
    this.dispose,
  });

  final AuthStore store;
  final AuthPhoneNumberBackend backend;
  final AuthPhoneNumberBackendConformanceFaultController faults;
  final FutureOr<bool> Function(String userId) hardDeleteUser;
  final FutureOr<void> Function()? dispose;
}

final class AuthPhoneNumberBackendConformanceFailure implements Exception {
  const AuthPhoneNumberBackendConformanceFailure(this.caseId, this.cause);

  final String caseId;
  final Object cause;

  @override
  String toString() =>
      'AuthPhoneNumberBackendConformanceFailure($caseId): $cause';
}

final class AuthPhoneNumberBackendConformanceCase {
  const AuthPhoneNumberBackendConformanceCase({
    required this.id,
    required this.description,
    required Future<void> Function() run,
  }) : _run = run;

  final String id;
  final String description;
  final Future<void> Function() _run;

  Future<void> run() => _run();
}

/// Reusable transaction contract for durable phone-auth adapters.
///
/// Adapters run every case against their real database transaction and connect
/// [AuthPhoneNumberBackendConformanceFaultController] to deterministic
/// database faults. The suite accepts no process-local fallback.
final class AuthPhoneNumberBackendConformanceSuite {
  AuthPhoneNumberBackendConformanceSuite(this.createFixture);

  final AuthPhoneNumberBackendConformanceFactory createFixture;

  List<AuthPhoneNumberBackendConformanceCase> get cases => [
    _case(
      'issue_replay_binding',
      'Issue receipts are payload-bound.',
      _issueReplay,
    ),
    _case(
      'verification_contention',
      'Exactly one concurrent verification commits.',
      _verificationContention,
    ),
    _case(
      'attempt_lockout',
      'Failed attempts are bounded and lock the challenge.',
      _attemptLockout,
    ),
    _case(
      'expiry',
      'Expired challenges cannot create or authenticate a user.',
      _expiry,
    ),
    _case(
      'issue_rollback',
      'An issuance fault restores the previous challenge.',
      _issueRollback,
    ),
    _case(
      'verification_rollback',
      'A verification fault restores challenge, user, and identity state.',
      _verificationRollback,
    ),
    _case(
      'hard_delete',
      'Hard deletion scrubs phone credentials and rejects user-ID reuse.',
      _hardDelete,
    ),
  ];

  AuthPhoneNumberBackendConformanceCase _case(
    String id,
    String description,
    Future<void> Function(AuthPhoneNumberBackendConformanceFixture fixture)
    body,
  ) => AuthPhoneNumberBackendConformanceCase(
    id: id,
    description: description,
    run: () => _withFixture(id, body),
  );

  Future<void> _withFixture(
    String id,
    Future<void> Function(AuthPhoneNumberBackendConformanceFixture fixture)
    body,
  ) async {
    final fixture = await Future.sync(createFixture);
    try {
      await body(fixture);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AuthPhoneNumberBackendConformanceFailure(id, error),
        stackTrace,
      );
    } finally {
      await Future.sync(() => fixture.dispose?.call());
    }
  }

  Future<void> _issueReplay(
    AuthPhoneNumberBackendConformanceFixture fixture,
  ) async {
    final first = _issue(id: 'conformance-issue');
    _require(
      (await fixture.backend.issuePhoneNumberCode(first)).status ==
          AuthPhoneNumberIssueStatus.issued,
      'first issuance did not commit',
    );
    _require(
      (await fixture.backend.issuePhoneNumberCode(first)).status ==
          AuthPhoneNumberIssueStatus.replayed,
      'exact issuance did not replay',
    );
    _require(
      (await fixture.backend.issuePhoneNumberCode(
            _issue(id: 'conformance-issue', digest: 'different-digest'),
          )).status ==
          AuthPhoneNumberIssueStatus.replayMismatch,
      'issue ID was rebound to another digest',
    );
  }

  Future<void> _verificationContention(
    AuthPhoneNumberBackendConformanceFixture fixture,
  ) async {
    await fixture.backend.issuePhoneNumberCode(_issue());
    final command = _verify(candidateId: 'conformance-user');
    final results = await Future.wait([
      Future.sync(() => fixture.backend.verifyPhoneNumberCode(command)),
      Future.sync(() => fixture.backend.verifyPhoneNumberCode(command)),
      Future.sync(() => fixture.backend.verifyPhoneNumberCode(command)),
    ]);
    _require(
      results
              .where(
                (result) =>
                    result.status == AuthPhoneNumberVerifyStatus.verified,
              )
              .length ==
          1,
      'verification committed more or less than once',
    );
    final identity = await fixture.backend.findPhoneNumberIdentity(
      '+15555550123',
    );
    _require(
      identity?.userId == 'conformance-user',
      'phone identity was not bound to the committed user',
    );
  }

  Future<void> _attemptLockout(
    AuthPhoneNumberBackendConformanceFixture fixture,
  ) async {
    await fixture.backend.issuePhoneNumberCode(_issue(maxAttempts: 2));
    final first = await fixture.backend.verifyPhoneNumberCode(
      _verify(digest: 'wrong-1'),
    );
    final second = await fixture.backend.verifyPhoneNumberCode(
      _verify(digest: 'wrong-2'),
    );
    final correct = await fixture.backend.verifyPhoneNumberCode(_verify());
    _require(
      first.status == AuthPhoneNumberVerifyStatus.invalid &&
          second.status == AuthPhoneNumberVerifyStatus.tooManyAttempts &&
          correct.status == AuthPhoneNumberVerifyStatus.tooManyAttempts,
      'bounded attempt lockout was not persistent',
    );
  }

  Future<void> _expiry(AuthPhoneNumberBackendConformanceFixture fixture) async {
    await fixture.backend.issuePhoneNumberCode(
      _issue(expiresAt: _now.add(const Duration(seconds: 1))),
    );
    final result = await fixture.backend.verifyPhoneNumberCode(
      _verify(
        candidateId: 'conformance-user',
        now: _now.add(const Duration(seconds: 1)),
      ),
    );
    _require(
      result.status == AuthPhoneNumberVerifyStatus.expired,
      'expired challenge authenticated',
    );
    _require(
      await fixture.store.users.findById('conformance-user') == null,
      'expired challenge created a user',
    );
  }

  Future<void> _issueRollback(
    AuthPhoneNumberBackendConformanceFixture fixture,
  ) async {
    await fixture.backend.issuePhoneNumberCode(_issue(id: 'original'));
    fixture.faults.failNext(AuthPhoneNumberBackendConformanceFaultPoint.issue);
    await _expectFailure(
      () => fixture.backend.issuePhoneNumberCode(
        _issue(id: 'replacement', digest: 'replacement'),
      ),
    );
    final result = await fixture.backend.verifyPhoneNumberCode(
      _verify(candidateId: 'conformance-user'),
    );
    _require(
      result.status == AuthPhoneNumberVerifyStatus.verified,
      'issuance rollback lost the previous challenge',
    );
  }

  Future<void> _verificationRollback(
    AuthPhoneNumberBackendConformanceFixture fixture,
  ) async {
    await fixture.backend.issuePhoneNumberCode(_issue());
    fixture.faults.failNext(AuthPhoneNumberBackendConformanceFaultPoint.verify);
    await _expectFailure(
      () => fixture.backend.verifyPhoneNumberCode(
        _verify(candidateId: 'conformance-user'),
      ),
    );
    _require(
      await fixture.store.users.findById('conformance-user') == null,
      'verification fault left a user',
    );
    _require(
      await fixture.backend.findPhoneNumberIdentity('+15555550123') == null,
      'verification fault left an identity',
    );
    final retry = await fixture.backend.verifyPhoneNumberCode(
      _verify(candidateId: 'conformance-user'),
    );
    _require(
      retry.status == AuthPhoneNumberVerifyStatus.verified,
      'verification fault consumed the challenge',
    );
  }

  Future<void> _hardDelete(
    AuthPhoneNumberBackendConformanceFixture fixture,
  ) async {
    await fixture.backend.issuePhoneNumberCode(_issue());
    final verified = await fixture.backend.verifyPhoneNumberCode(
      _verify(candidateId: 'conformance-user'),
    );
    _require(verified.committed, 'setup verification failed');
    _require(
      await fixture.hardDeleteUser('conformance-user'),
      'hard deletion failed',
    );
    _require(
      await fixture.backend.findPhoneNumberIdentity('+15555550123') == null,
      'hard deletion retained the phone identity',
    );
    await fixture.backend.issuePhoneNumberCode(_issue(id: 'post-delete-issue'));
    final reused = await fixture.backend.verifyPhoneNumberCode(
      _verify(candidateId: 'conformance-user'),
    );
    _require(
      reused.status == AuthPhoneNumberVerifyStatus.conflict,
      'hard-deleted user ID was reusable',
    );
  }
}

final _now = DateTime.utc(2030, 1, 1);

AuthPhoneNumberIssueCodeCommand _issue({
  String id = 'conformance-issue',
  String digest = 'conformance-digest',
  int maxAttempts = 3,
  DateTime? expiresAt,
}) => AuthPhoneNumberIssueCodeCommand(
  verification: AuthPhoneNumberVerification(
    id: id,
    phoneNumber: '+15555550123',
    codeDigest: digest,
    createdAt: _now,
    expiresAt: expiresAt ?? _now.add(const Duration(minutes: 5)),
    maxAttempts: maxAttempts,
  ),
);

AuthPhoneNumberVerifyCodeCommand _verify({
  String digest = 'conformance-digest',
  String? candidateId,
  DateTime? now,
}) => AuthPhoneNumberVerifyCodeCommand(
  phoneNumber: '+15555550123',
  codeDigest: digest,
  now: now ?? _now,
  candidateUser: candidateId == null ? null : AuthUser(id: candidateId),
);

Future<void> _expectFailure(FutureOr<Object?> Function() action) async {
  try {
    await Future.sync(action);
  } catch (_) {
    return;
  }
  throw StateError('expected injected backend failure');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
