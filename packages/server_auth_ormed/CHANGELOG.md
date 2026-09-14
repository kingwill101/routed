## 0.1.2 - 2026-09-08

- Use Ormed native atomic batches for invitation replacement when the driver
  supports them, preserving pending invitations when a replacement fails.
- Add transactional Ormed remember-token persistence for restart-safe local
  session examples.

## 0.1.1 - 2026-09-08

- Support Ormed drivers without callback transaction boundaries, including
  Cloudflare D1, using the driver's normal query and bulk APIs.
- Serialize operations per database handle when transactions are unavailable.

## 0.1.0 - 2026-09-07

- Add Ormed query-builder-backed core auth and organization stores and
  migrations.
