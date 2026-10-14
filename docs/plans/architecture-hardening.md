# Pre-alpha architecture hardening — ordered integration plan

**Status:** Proposed execution sequence, 2026-10-14, for review before implementing. **Scope:** harden current Godot/TinyMMO-based single-World architecture now, before new systems depend on it; future multi-World process extraction remains governed by accepted [Economy C1–C5](../architecture/economy/README.md) and [World topology ADR](../architecture/world-instance-architecture.md).

**Branch baseline at review:** `main` `8d6230a`; open [Marketplace PR #1](https://github.com/PatrykCieszynski/Mandate-of-Three/pull/1), head `shop` `fa20d77`, adds account-wide marketplace/Exchange/Auction to **shop**, not yet **main**. Auction PR #2 was merged **into `shop`**. Update hashes/status when integration happens.

## Purpose and non-goals

The goal is **not** a cosmetic file shuffle, a generic ORM, a Kafka bus or immediate PostgreSQL deployment. Refactor boundaries that will be expensive to change once gameplay/content begins depending on them:

- trusted session and World request identity;
- one authoritative account wallet, UID custody and atomic economic command API;
- persistence transaction owner separate from World presentation/routing;
- event/snapshot invalidation between Economy state and combat cache;
- explicit single-World instance/session lifecycle that can later support host/process fencing;
- bounded impact of economic writes on dense 60 Hz combat.

Preserve currently tested gameplay and native CEF behavior. A code package owns a small coherent contract and its failure-case tests; avoid a multi-week big-bang extraction. Do not confuse new product functionality with refactoring.

## Delivery order (separate reviewable PRs)

| Package | When | Scope and acceptance gate |
| --- | --- | --- |
| **I0 — integrate Marketplace/Auction** | First after review | Bring latest `main` into `shop` **without rewriting history**; inspect diff/conflicts; run standard smoke, marketplace/Exchange purchase/race/recovery tests, UI build/bridge checks and CI; merge PR #1 with normal no-ff workflow when accepted. Do not silently include new Shop UX/payout semantics. |
| **A1 — Gateway request/session lifecycle** | Before public alpha, preferably first technical fix | Remove resolved/expired `pending_requests` entries; cap pending work; add session TTL, pruning, logout/revocation and replay-safe delayed reply handling. Test repeated requests/timeouts and session expiry. |
| **A2 — World RPC authorization boundary** | Before public alpha | Restrict client-selected handler names to allowed operations; validate authenticated peer and authorized instance/context at a shared ingress boundary; no implicit default-instance authorization on unknown instance IDs. Individual handler domain checks remain. Test forged instance ID/handler, unauthenticated requests and legitimate flows. |
| **A3 — authoritative World/economy API** | Immediately after integration/security | Keep SQLite and existing stores; narrow WorldDatabase to connection/lifecycle/dirty checkpoints; route economic use cases via one explicit application boundary with typed/validated intents, stable operation IDs, receipts and domain result/change facts. Keep store-level transaction boundaries shared and avoid nested COMMITs. Test purchase vs cancel/edit, same-ID replay, UID custody, source context, rollback and wallet reconciliation. |
| **A4 — apply accepted Shop UX/payout deltas** | After A3 foundation | Implement Inventory-capacity-backed withdrawal, negotiated-price listings with no buy-now at zero, and account `claimable_yang` ledger + claim UI. Separate product/schema migration PRs when appropriate; use [decision delta](../decisions/marketplace-v2-gaps.md). **Do not** implement bidder offers now. |
| **A5 — projection/versioning and tick budget** | Before dense combat + large player tests | Make committed facts/revisions drive inventory/equipment/Walet views; invalidate and recompute derived World stats once safely, not via synchronous SQL per hit. Measure costs of COMMIT vs snapshot construction vs fan-out in actual loaded combat. Improve main-thread tails with evidence; do not automatically move the SQLite writer to worker. |
| **A6 — intra-World transfers and session state machine** | Before CH/multi-process work | Centralize 'can transfer?' and server countdown/cancel/interrupt rules; gate character mutations and flush pending progress/Yang; ensure single active session in current World. Model attempt/epoch IDs with clean abort boundaries, then test disconnect/cancel races. Multi-host registry and PostgreSQL stay future work. |
| **D1 — documentation layout sweep** | In progress independently | Active docs moved into domain folders and obsolete plans removed in the docs-only topic branch. After I0, review additional `shop` reports and evidence separately. |

A1 and A2 may be reordered or combined only if tests and review stay focused. A3/A4 can use multiple small PRs; don't enforce artificial abstractions solely to match the future process topology.

## Findings motivating the packages (static inspection only)

1. **Gateway pending-request retention (confirmed code path).** `source/server/gateway/http_server.gd` inserts into `pending_requests` and resolves responses/timeouts without erasing entries. `NetRequest.resolve` marks completion but cannot release its Gateway dictionary entry. Fix lifetime and late-result behavior first.
2. **Gateway session retirement (design/security gap).** HTTP `sessions` are created but have no visible expiry/pruning; World auth `token_list` consumes valid tokens on use, but stale unconsumed tokens have no visible expiry. Master uses last-login-wins kick semantics without a completed fenced handoff. Define single-session guarantees before cross-World transitions.
3. **World request boundary (audit required; exploit unproven).** `WorldServer._data_request` receives `type` and `instance_id` from peer, dynamically loads handler scripts and falls back to the default instance when the requested ID cannot be resolved. Verify explicit operation allowlist, context membership and command-specific authority before accepting public clients.
4. **Marketplace latency (measured risk, not yet production SLA).** `shop` Auction D2 Windows fixture at 10k offers measured combat-only tick interval p99 ~16.7 ms; loaded sequential economic writes p99 ~24.2 ms and write-burst p99 ~36.8 ms (with larger max tails). Read search is already asynchronous through SOCI. Profile COMMIT, projection and publish/fan-out separately rather than reflexively replacing the writer.
5. **Architecture mismatch by design, not hidden regression.** `shop` uses `account_claim` on cancel and direct seller credit; new C3 calls for bag-space-sensitive Shop withdrawal and `claimable_yang`, plus price-free listings. Track explicitly in [Marketplace delta](../decisions/marketplace-v2-gaps.md).

These are distinct from the accepted future **C2 durable cross-process admission** or **C5 multi-World fencing**; those are **not** promises about the current single-process prototype.

## Hard quality gates for each package

- Document the invariant(s), current failure mode, exact allowed behavior change and rollback path before touching code.
- Run `git diff --check`, boundary guards and `tests/run-smoke.ps1` (Godot 4.7.2 + Node). Add only specific relevant existing integration suites. Don't add unit tests only because a class moved.
- Economic mutation package: test crash/restart WAL receipts, duplicate operation ID and changed payload, balances/reserves conservation, lost response, race across buyers, UID custody, bag capacity and no partial COMMIT. Retest native CEF if actual client/UI bridge changes.
- Gateway/RPC package: test unknown/expired sessions, identity spoofing, timeout/late reply, correct instance ownership, reconnect, and no regression to Gateway → Master → World login/character flow.
- Performance package: use same machine/settings before-and-after, `market_load` combat+search+write and separate per-step wall times; compare tick p95/p99/max under load. Not a promise of a global SLA.
- Never merge generated logs, runtime DBs, credentials or local native addons. Rehearse migrations on backups and verify old persisted data before public data reset/upgrade.

## Merge & deployment principles

- The **integration merge gate** (CI, diff/review, existing behavior) differs from the **public alpha gate** (session security, final Marketplace UX/payout, native acceptance and platform needs).
- The `shop` branch must absorb commits added to `main` after its base. Keep history; do not force-push or squash away already reviewed topic merges.
- Do not refactor WorldDatabase and Shop schema in the same PR as a bugfix to HTTP sessions.
- Use [current persistence policy](../architecture/persistence-policy.md) as runtime truth until an explicit implementation PR changes it. Accepted [C1–C5](../architecture/economy/README.md) specify the destination, not the current implementation.
- When we need two independent World Processes sharing one realm, plan the durable Economy Service, account-scoped admission/recovery and PostgreSQL as an explicit later milestone. Internal boundaries hardened now should reduce, not conceal, that migration.
