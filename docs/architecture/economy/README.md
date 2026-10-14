# Economy V2 — contract index

**Scope:** design contracts for a future realm-wide economy shared by World Processes on one or many hosts. These documents are **not** a request to implement a service, change the live SQLite schema, or start an infrastructure refactor.

**State of decisions (2026-10-14):** C1–C5 are accepted **at the architectural level** after a cross-contract consistency review. Acceptance defines future safety guarantees and ownership boundaries; it does **not** claim the runtime implements distributed Economy or authorize migration. Wire formats, concrete limits and some gameplay/recovery behavior remain deferred.

| Contract | Status | Concern |
| --- | --- | --- |
| [C1 — ownership](C1-ownership.md) | **Accepted** | One authority for account money, durable items and economic mutations; World for simulation |
| [C2 — commands](C2-commands.md) | **Accepted (architecture)** | Stable operation identity, durable admission/results, retry and overload |
| [C3 — transactions](C3-transactions.md) | **Accepted (architecture)** | Atomic settlement, ground rewards, Yang batches and claimable Shop income |
| [C4 — synchronization](C4-synchronization.md) | **Accepted (architecture)** | Versioned snapshots, derived combat cache and in-flight operation barriers |
| [C5 — lifecycle](C5-lifecycle.md) | **Accepted (architecture)** | Server-controlled cancellable CH handoff, session fencing, lost hosts; implementation parameters deferred |

## Accepted cross-cutting direction

- A realm (e.g. Season or Classic) has one **logical economic authority** independent of its number of CH, layers, dungeons, World Processes or machines. Season and Classic economies are isolated, even if infrastructure is shared.
- Account Yang is shared by all characters of that account **within one realm**. Critical currency/item/equipment/trade operations commit durably and atomically before success is acknowledged. Shop/Auction seller revenue is **accepted** as separate account-level `claimable_yang` to be manually claimed in the shop panel; direct credit is not the target future design.
- The future Economy Service is a separate process, communicating asynchronously with World Processes. One logical authority need not mean a single SQL worker or one physical instance forever.
- The current development environment remains **single-process World + local SQLite**. PostgreSQL and process extraction come later; do not replace working economy code or add threads just to conform to this design.
- Simulated gameplay must not wait synchronously for database/network round trips. A particular economic operation may remain pending until its durable result is known.

## Cross-contract consistency checks

| Scenario | Required guarantee |
| --- | --- |
| Economy admits a command, then the reply or World host disappears | C2 makes admitted work discoverable and replay-safe; C3 commits its economic facts at most once |
| Character changes CH with old admitted commands in flight | C5 fences old **new** admissions; C2 exposes unresolved earlier work; C4 reconciles/blocks dependent gameplay until it is safe |
| Character changes CH with pending grinding Yang | C3 settles the batch once before a successful C5 handoff; a second earning owner cannot start before the first is fenced |
| Equipped item state changes while cached in World | C4 rejects stale revisions, invalidates combat effects and recomputes safely without SQL per attack |
| Offline Shop sale completes during seller's CH transfer | C3 atomically transfers custody and credits account `claimable_yang`; C4 refreshes derived views independently of seller's active session |
| Dungeon host crashes after a protected loot manifest commit | C3 preserves eligible unclaimed rewards for the time-limited stash; C5 does not promise resurrection of transient combat |

**Deferred without weakening these guarantees:** exact RPC/admission-log implementation, operation-ID encoding and retention, queue limits, Yang batch/lease mechanics, wallet/claim overflow rules, protected-loot criteria and world-boss policy, CH countdown length, failover UX and database deployment.

## Existing implementation and compatibility

The current [persistence policy](../persistence-policy.md) remains authoritative for the running prototype: RAM/dirty checkpoints for soft progression and some grinding Yang, immediate atomic item and critical Yang spending transactions. Current WorldDatabase, custody, Market, Exchange and auction integration are not changed by these design documents.

The separate [world instance architecture](../world-instance-architecture.md) covers dynamically created public channels, optional invisible layers, public DT-style and private dungeons, multi-process placement and remote hosts. Economy contracts reference it without duplicating the instance scheduler.

## Contract review rules

Each file separates **Accepted**, **Proposed / open**, **Failure contracts**, and **Current code / migration implications**. Do not infer a wire protocol, deployment topology or implementation task from examples. Update contract status only after a concrete decision; mark replaced designs superseded rather than silently rewriting history.

**Current status:** C1–C5 architectural docs have been merged to `main`. The [pre-alpha hardening plan](../../plans/architecture-hardening.md) improves internal World/Shop/session boundaries **now**, while preserving single-World + SQLite until a distinct process-extraction milestone. The [Marketplace decision delta](../../decisions/marketplace-v2-gaps.md) separates newer product decisions from still-open `shop` implementation. Any later documentation relocation must preserve links and historical evidence.
