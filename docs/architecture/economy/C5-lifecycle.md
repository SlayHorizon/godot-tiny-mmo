# C5 — handoff, sessions and failure recovery

**Status: Accepted — architectural behavior only (2026-10-14).** Exact RPC schema, timeouts, UX and implementation details remain open; this document does not authorize a service migration.

## Accepted constraints inherited from C1 and world topology

A CH, overflow layer, public dungeon and private party dungeon are MapInstances hosted by World Processes, possibly on different machines. One economy authority serves the entire realm, independent of instance placement. A character must not have two active authoritative gameplay sessions.

## Accepted architectural rules — multi-World handoff and outages

- **Session authority:** prefer one active character per account *within a realm* (cross-realm login policy remains open). Gateway/realm session authority issues an owner/lease/monotonic epoch for each active character; Economy admission validates the current authorized actor/session context and fences newly submitted commands from stale Worlds. Process/instance IDs are not themselves proof of authority.
- **Controlled handoff (no live-map migration):** validate eligibility and reserve a target MapInstance; run a cancellable server-controlled countdown; revalidate eligibility at its end; gate new character-originated economic/gameplay intents; settle required pending Yang and soft progression checkpoints; revoke/fence source authority; load target snapshots and reconcile accepted economic operations; activate exactly one target session; then release the source. Each stage must be observable and recoverable; failed destination activation must allow controlled rollback (only while safe), retry or reconnect, never dual activation.
- **In-flight economics:** commands admitted under an old epoch may complete. Before the new World permits actions depending on economy/equipment state, it must discover unresolved old-epoch admissions (or establish an equivalent authoritative completion barrier), reconcile their eventual terminal outcomes and rehydrate the affected revisions. A one-time snapshot cannot prove safety when an admitted command may commit afterward. Epoch fencing applies to new admissions, not a retroactive rollback of committed transactions.
- **Server-authorized CH change, not client-triggered teleport:** source World / session authority checks transition eligibility *before* fencing. Deny or postpone while in combat/recently damaged (a tunable combat cooldown), with open direct trade, active shop editing / other exclusive item interaction, or with mutually dependent economic work that has not been reconciled. An **approximately five-second delay after a completed direct trade or other sensitive transaction** is a gameplay/configuration candidate, **not a substitute for checking pending operations or a durability guarantee**; the historical Metin2 value is not relied on here.
- **Character-scoped economic admission gate:** after the countdown and a final eligibility check, during committed transfer preparation, stop accepting new inventory/trade/shop-edit/other character-originated economic mutations from this old World session and close incompatible interaction UIs, without stopping the realm Economy Service or blocking unrelated accounts. Existing posted shop listings/offline sales may continue under Economy authority; only World-originated character access is gated. If preparations fail before authority moves, safely reopen admissions on the still-active source session.
- **Multi-message client/server CH procedure:** the client may **request** a destination CH and later request **cancellation**; only the server can admit the transition and determine a server-time countdown deadline. The server replies with acceptance/rejection and reasons or prerequisites, announces countdown state, can interrupt the attempt when gameplay eligibility changes (e.g. renewed combat/damage, opened trade), and informs the client of cancellation, transfer progress and terminal activation/reconnect. The client displays a countdown and cancel control but does not decide completion from its own timer. An attempt/transfer identity should correlate retries and concurrent cancel/complete messages; exact wire fields are later design.
- **Cancellation boundary:** voluntary cancel and automatic gameplay interruption are valid while the transition is still safely abortable (countdown, or preparation before irreversible source fencing). After the source session epoch is fenced/authority moved, cancellation must **not** resurrect the old session; it becomes recovery/reconnect on the authoritative session. Racing cancel, countdown completion, fencing and delayed packets must yield one server-defined outcome. On safe abort, release the target reservation and any admission gate, retaining already committed economic transactions.
- **Drain and freeze are distinct:** after the gate, settle required pending Yang grants, enumerate/reconcile earlier admitted character commands (or gate their dependent effects) and checkpoint needed progression. A fixed cooldown alone cannot prove all SQL/network commits finished. Reserve destination capacity and fence the source epoch before target activation. If an already-admitted command finishes late, the destination observes authoritative revisions/receipts before enabling affected actions; it must not issue a duplicate with a new operation ID.

- **Failure handling:** when a World or host dies, leases expire/are revoked and the gateway restores one authorized login path. Item/currency/receipts survive in Economy; transient mobs/ordinary ground drops and uncheckpointed soft progression/Yang may not. Protected dungeon reward manifests survive; continuous combat/dungeon progress is **not** promised. Do not expose the same live character in two instances while recovering.
- **Economy outage:** leave World movement/combat operating on a safe cached snapshot; economic actions fail closed or remain pending. Never fabricate committed success. On recovery, query outcomes and rehydrate before re-enabling item-dependent mutations.
- **First deployment stage:** controlled client reconnect to the target World is acceptable. Host discovery, leases, health checks and placement can first run with multiple processes on one machine; moving hosts to other machines is a later deployment step. No hot migration, Kubernetes or distributed transaction spanning World and Economy is assumed.

### Tests for later implementation

Source fails before source fencing; destination fails after reservation; lost activation ACK; replayed session epoch on another host; stale World submits a new purchase; admitted purchase finishes after CH switch; pending Yang checkpoint fails; Economy unavailable during reconnect; dungeon host dies with committed/unclaimed manifest.

## Implementation details still open — do not block architectural acceptance

- Identity/lease issuer, epoch renewal and revocation persistence, trusted delegation, transfer-ticket validation and session recovery after coordinator failure.
- Exact client/server messages, transfer-attempt IDs and stale-response handling; countdown length, post-trade cooldown and which combat/interaction events interrupt it. Gameplay configuration is separate from safety.
- Transfer deadlines, pre-fence cancellation/rollback UX, client reconnect tickets and what to display during Economy/World outage.
- Instance/process shutdown draining, backups, monitoring and operational failover.
- Public dungeon rejoin policy, private run closure/reset/lockouts, and host-crash gameplay recovery details. Durable protected loot remains governed by C3.

## Failure cases to test later

Peer reuse, split-brain World claims, source death during handoff, target death after reservation, delayed response from prior session, crash after durable loot claim but before ground-drop deletion, Economy restart during a purchase.

## Current code / migration

Current single-process instance lifecycle, session admission and SQLite graceful save remain authoritative. No cross-process transfer, realm-wide session coordinator or failure failover is asserted to exist by this document. See [world instance architecture](../world-instance-architecture.md).
