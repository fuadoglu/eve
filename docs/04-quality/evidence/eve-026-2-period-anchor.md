# EVE-026.2 — Calendar anchor və billing period application

Status: **component acceptance passed; closes when PR is merged**. This pure local component computes a proposed period only after the caller supplies a server-verified payment timestamp. It does not persist subscriptions, verify provider events, or grant entitlements.

## Behavior

- Applies monthly/yearly periods in `Asia/Baku`; stores returned boundaries as UTC RFC3339 instants and returns the matching `anchor_day`, `anchor_month`, `anchor_time`, and timezone.
- Keeps a day-31 anchor across February clamp, then returns to day 31 in March. Leap-year day 29 is restored when February permits it.
- Starts at the latest of verified payment, prior paid period end, and explicitly supplied trial end. Early renewal is queued at the existing period boundary; remaining trial time is not discarded.
- Plan changes start at the existing boundary, keep day/time anchor, and set the new period month from that boundary. No pro-rata price or provider behavior is inferred.
- Rejects malformed/nonexistent calendar timestamps, unsupported plan values, invalid anchor ranges/time strings, non-positive existing period ranges, and unsupported timezone identifiers. Timestamp and SQL-time fractional precision is preserved to PostgreSQL's six-digit microsecond precision.

## Verification

- `pnpm test:billing` — **12/12 passed**, including seven period-helper cases covering Jan 31→February clamp→March restoration, leap-year month end, Feb 29 annual recurrence, early renewal, trial-end start, plan switch, UTC/Baku conversion, millisecond and microsecond precision, and negative validation.
- `pnpm typecheck` — passed (Node 24.22.2 / pnpm 12.18.0).
- `pnpm build` — passed.
- `node scripts/docs-check.mjs` — passed, 74 Markdown files.
- `node scripts/verify-contracts.mjs` — passed, 118 operations, 56 tables, 256 bindings, 90 acyclic packages, 16 trace rows, 36 scenarios.
- `/tmp/eve0222-schema-venv/bin/python scripts/validate-schemas.py` — passed, 207 schemas; 12 positive and 20 negative examples.
- `python3 scripts/verify-storage-config.py` — passed, seven private buckets aligned.
- `node scripts/test-prototype.mjs` — passed, 71 synthetic VM/fake-DOM assertions; not billing UI/backend proof.
- `git diff --check` — passed.

GitHub PostgreSQL/synthetic Supabase jobs add repo-wide regression evidence; this package has no migration. No provider sandbox, hosted billing, persisted entitlement, or production behavior is claimed. AT25 concurrency and full AT28 expiry/safety/task-window acceptance remain open at their owning integration/release scopes.
