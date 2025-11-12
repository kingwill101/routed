## 0.2.0

- `StatefulPropertyRunner` now accepts a distinct `CommandType` generic so
  invariants and update functions keep full type information even when command
  objects differ from the model type. This fixes analyzer complaints in custom
  runners and makes property harness extensions easier to compose.

## 0.1.0

- Initial public release aligned with the routed ecosystem workspace.
- Adds generators and shrinking support used by the routed test suite.
