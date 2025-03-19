/// A property-based test runner for verifying code behaves correctly for all possible inputs.
///
/// Property testers generate test inputs and verify that certain properties hold true
/// across all generated cases. They support common testing patterns like checking
/// invariants and function equivalence.
abstract class PropertyTester {
  /// Tests if a property holds true for all generated inputs.
  ///
  /// Takes a [property] function that should not throw any exceptions for valid inputs.
  /// The property will be checked against multiple generated test cases.
  Future<void> check(Future<void> Function(dynamic input) property);

  /// Tests if an invariant condition holds true for all generated inputs.
  ///
  /// The [invariant] function should return true for valid inputs. If it returns
  /// false for any case, the test will fail.
  Future<void> checkInvariant(Future<bool> Function(dynamic input) invariant);

  /// Tests if two functions produce identical outputs for all possible inputs.
  ///
  /// Verifies that [f1] and [f2] return equal results when called with the same
  /// generated inputs. This is useful for testing implementations against a reference
  /// implementation or testing refactored code against the original version.
  Future<void> checkEquivalence(Future<dynamic> Function(dynamic input) f1,
      Future<dynamic> Function(dynamic input) f2);
}
