**High Priority / Critical:**

1.  **Refactor `DateTimeGenerator`:**
    - [x] Remove static variables (`_lastGeneratedDate`, `_generatedMonths`).
    - [x] Make generation stateless, relying only on `Random`, `min`, `max`, `utc`.
    - [x] Simplify generation logic, removing special test cases (epoch, month distribution).
    - [x] Simplify shrinking logic (target `min`/epoch, simpler date/time components).
    - [x] Remove chronological order enforcement logic.
    - [x] Update `datetime_generator_test.dart` to reflect the new stateless logic and remove tests relying on static state/special cases.
2.  **Update README.md:**
    - [x] Replace old API examples (`Any`) with new ones using `Gen`, `Specialized`, `Chaos`.
    - [x] Add sections explaining generator composition with combinators (`map`, `flatMap`, `where`, `list`, tuples, etc.).
    - [x] Add examples of using `PropertyTestRunner` and `PropertyConfig`.
    - [x] Add sections on Chaos testing and Stateful testing with examples.
    - [x] Explain reproducibility using `PropertyConfig` and seeds.
3.  **Report Seed on Failure:**
    - [x] Add a `seed` field (or representation of the `Random` state) to `PropertyResult`.
    - [x] Modify `PropertyTestRunner` to capture the seed used (handle default seed 42 vs. user-provided `Random`).
    - [x] Update `PropertyTestReporter` (`report` getter in `PropertyResult` or standalone class) to include the seed in the failure output.
4.  **Remove Obsolete Files:**
    - [x] Delete `lib/src/payload_builder.dart`.
    - [x] Delete `lib/src/record.dart`.
    - [x] Delete `lib/src/generators.dart` (containing old `Any` and `ChaoticString`).
    - [x] Delete `lib/src/property_test.dart` (containing `ForAllTester`, old `Generator` typedef, etc.).
    - [x] Delete `test/property/record_test.dart`.
    - [x] Ensure no examples or tests still reference the deleted files/classes (especially `Any`).
5.  **Require `Random` in `Generator.generate`:**
    - [x] Change signature from `generate([Random? random])` to `generate(Random random)`.
    - [x] Update all generator implementations (`primitive_generators`, `chaos_generators`, `specialized_generators`, `generator_base` combinators) to accept the required `Random` instance and remove internal `?? Random()` defaults.
    - [x] Ensure `PropertyTestRunner` correctly passes the configured `Random` instance.

**Medium Priority / Recommended:**

6.  **Add Comprehensive DartDoc:**
    - [x] Document main public classes (`Generator`, `PropertyTestRunner`, `ShrinkableValue`, `PropertyConfig`, `PropertyResult`, `ChaosConfig`, `Gen`, `Specialized`, `Chaos`).
    - [x] Document stateful testing concepts (`Command`, `StatefulPropertyBuilder`, `StatefulPropertyRunner`).
    - [ ] Document _all_ public methods, especially generator combinators.
    - [ ] Explain the purpose, configuration, and shrinking strategy of each generator type (`Gen`, `Specialized`, `Chaos`) in more detail.
7.  **Expand Test Coverage:**
    - [x] Add tests for `PropertyTestRunner` focusing on shrinking behavior (`shrinking_test.dart`).
    - [ ] Add explicit tests for all primitive generators in `Gen`.
    - [ ] Add tests for all chaos generators in `Chaos` and `ChaosConfig`.
    - [x] Add tests for generator combinators (`generator_composition_test.dart`).
    - [ ] Add tests for stateful testing components (`CommandSequence`, `StatefulPropertyBuilder`, `StatefulPropertyRunner`, precondition-aware shrinking).
8.  **Clarify `Gen.payload`:**
    - [ ] Add documentation explaining its use case (simple, schema-based maps) and contrast it with `Gen.map`/tuples. Consider if it should be deprecated or kept for convenience.

**Low Priority / Future Considerations:**

9.  **Optimize Stateful Shrinking:**
    - [ ] Investigate if `shrinkWithPreconditions` performance can be improved for very long command sequences (potentially complex).
10. **Improve Documentation Quality:**
    - [ ] Follow Dart documentation best practices (see dartdoc.mdc rules).
    - [ ] Add examples to all public API documentation.
    - [ ] Document shrinking strategies for each generator type in more detail.
    - [ ] Add cross-references between related classes and methods.
    - [ ] Include property-based testing best practices and patterns.
11. **Enhance Tuple Generators:**
    - [x] Add comprehensive tests for all tuple generators (TupleGenerator2, TupleGenerator3, TupleGenerator4).
    - [ ] Document tuple generator shrinking strategies.
    - [ ] Consider adding TupleGenerator5 and beyond if needed.
    - [ ] Add examples of common tuple generator use cases.
