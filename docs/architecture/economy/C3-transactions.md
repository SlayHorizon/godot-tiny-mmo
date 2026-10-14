# C3 — transactions, persistence and rewards

**Status: Accepted — architectural contract (2026-10-14).** Gameplay thresholds and storage/recovery implementation details remain open; this does not authorize a code or schema migration.

## Accepted constraints inherited from C1

Critical ItemInstance ownership/custody, trade, equipment, purchase, escrow, Yang spending and receipt outcomes must be atomic and durable before success is acknowledged. Ordinary unclaimed ground drops may be transient World state. Account Yang is realm-wide, not character- or channel-local.

## Accepted C3 decisions (2026-10-14)

- **Ordinary mob-ground Yang may use bounded, batched accrual**, as in the current prototype's positive `pending_currency_delta` and approximately 30-second checkpoints. A sudden World Process crash may lose only the still-uncommitted portion of this **soft grinding income**; this accepted risk does **not** apply to already committed balances or item/trade/Shop outcomes.
- **Critical spending and economic mutations must settle atomically.** A purchase, upgrade, trade, Exchange order or other meaningful spend must include any relevant pending income in its authoritative transaction (or first safely reconcile it), check funds and commit the item/currency/receipt changes together. Uncommitted client-visible farming income cannot be used to bypass a durable balance check.
- **Before cross-process handoff**, outstanding locally owned Yang deltas must be safely committed/reconciled and the original earning authority fenced; never transfer and then allow both old and new World Processes to flush the same accrual. A failed required checkpoint means the handoff cannot be confirmed as successful; specify recovery and retry when designing C5.
- Account Yang belongs to the realm Economy authority, not to CH/instance/World. The final multi-process batching protocol must have stable batch/grant identities, acknowledgements and duplicate-apply prevention, or another **equivalently safe single-writer/lease settlement mechanism**. The exact protocol and threshold are deliberately **not approved yet**.
- **Shop/Auction seller revenue is credited to an account-scoped, realm-scoped `claimable_yang` balance, not directly to spendable Yang.** The buyer's debit, item custody/ownership change, offer settlement, seller's claimable credit and idempotent receipt must commit **atomically**. Offline sellers and sellers playing on another World Process require no local wallet mutation to settle a sale. A sale is final after COMMIT even before the seller manually claims its revenue.
- **Claim seller revenue from the My Shop/market panel.** An authenticated `ClaimShopRevenue` command atomically moves the claimed amount from `claimable_yang` to the shared account wallet, with a stable `operation_id` and receipt. The same funds cannot be claimed twice, spent before claiming, or counted as both pending and spendable. The panel may aggregate the balance while keeping itemized sales history separately. In-game mail may notify the player but must not be the monetary ledger or create one mail per sale.
- Claim limits, wallet overflow/max-balance policy, full versus partial claim, and whether Auction and other sale sources use the exact same pool remain open for C3 implementation design. This is **future-state design**: current Shop/Exchange settlement logic and local SQLite runtime are not changed by this document.
- Local SQLite single-writer and existing `pending_currency_delta` behavior remain unchanged. This design does not approve a premature worker/process migration.

## Accepted shop inventory, listing and escrow semantics (2026-10-14)

- A player shop has a **shop-held item inventory/escrow** distinct from the character's regular Inventory. A shop item and its **listing terms** (fixed price, price-free/negotiable, later optional offers) are different conceptual concerns; they do **not** require distinct physical SQL tables.
- **Withdraw from shop** means transfer the item back to the character's Inventory **and remove its listing atomically**. If Inventory has no valid target footprint/space, reject the whole withdrawal; the item, shop custody and listing/terms remain unchanged. Do not silently add an extra cancelled-offer vault.
- **Remove fixed price** leaves the item in shop custody and keeps it visibly listed as **offer-only / negotiable**; it does not withdraw or destroy the listing. Price absent (`null`/explicit no-price mode) must **not** mean zero Yang or free instant purchase.
- **Change fixed price** updates only listing terms, with no transfer between inventories and no regular Inventory capacity requirement. Price removal/change and instant purchase of the same item compete through atomic offer/item state and revision checks; only one conflicting transition can win.
- **Built-in offers/negotiation are deferred.** A listing with no fixed price is currently only an informational **"do negocjacji" / "cena do uzgodnienia"** advertisement: no platform bid submission, bid acceptance, reserved bidder Yang, offline offer settlement or automatic sale. Players may arrange terms themselves and finish through ordinary, authoritative **direct player-to-player trade** when that gameplay flow is available.
- A shop-held UID remains in escrow while advertised and therefore **cannot be traded privately directly from shop custody**. The seller must first withdraw it into their Inventory (subject to normal footprint/capacity checks), atomically removing the listing, and only then offer it in direct trade. Never let the same UID be both tradable in a private exchange and available for shop buy-now at the same time.
- Listing/storage limits, any future built-in bid/acceptance/offer escrow, buy-now-plus-offers mode, and contact UX are deferred design topics. No implementation or schema change is authorized by this document.

## Accepted protected-loot direction — selected parameters remain open

**Motivation:** keep the familiar physical ground-loot experience and avoid a second inventory full of uncollected trash. A persisted reward manifest is only for selected high-value encounters/reward categories, not every mob or every item. Exact selection/rarity threshold is open. The chosen gameplay rule is not an entitlement to collect everything that drops.

| Encounter type | Ground pickup rights | Fallback for unclaimed *eligible protected* loot |
| --- | --- | --- |
| Solo dungeon | Initially exclusive to the solo player; ordinary pickup works | Player's bounded, time-limited reward stash |
| Party dungeon | Initially assigned per player using a later-defined gameplay policy; assignment expires after **approximately 60 seconds** (initial configurable policy), then any eligible party member may collect | At run closure/crash recovery, unclaimed protected loot becomes claimable from the **run's designated party leader's** time-limited stash |
| Ordinary mobs/Metins | Existing temporary ownership and eventual public pickup policy | No stash; unclaimed ground drops expire normally |
| Major world boss | Design separately, because public ownership release may conflict with fallback entitlement | Not yet decided |

- Do not bind a protected *party* drop irrevocably to its initial assigned player while also allowing other members to claim it. Its manifest instead records the current claim rights/state; the **first valid claim wins atomically** and precludes a stash copy.
- Snapshot the designated party leader for any fallback at reward-manifest creation, so party-leadership changes or party dissolution do not silently redirect rights. Whether leader-only fallback is fair and which exceptional rewards qualify remains a gameplay/product consideration, not a generic Economy ownership rule.
- The fallback stash has a **12-hour claim window** after the reward becomes available in the stash (normal run closure or crash recovery). Opening the stash must not implicitly consume other rewards, and an inventory-full claim must leave the reward pending without duplication. Exact size/caps and notification UX remain to be designed.
- Ordinary/low-value drops should **not** fill the stash. A manifest can describe selected guaranteed/valuable rewards; all other drops continue as transient MapInstance entities with the existing expiring pickup rights.
- A selected protected encounter must durably register its manifest/UIDs and claim policy **before exposing protected ground drops**. Claims, transition to a fallback stash and expiry are mutually exclusive durable state transitions: `on_ground -> claimed_by_character` **or** `on_ground -> stash_claimable -> claimed_by_character / expired`; never grant a second UID on recovery. A host crash with a committed manifest but no live instance can trigger fallback without silently consuming the rewards.
- The *award allocation formula* (damage contribution, party contribution, random distribution), the scope of "eligible party", loot visualization, and detailed dungeon run lifecycle belong to gameplay/dungeon design, not this economic durability contract.

**Status of this section:** accepted direction for selected valuable dungeon rewards: physical drops, solo-owner fallback, party loot becoming shareable after approximately one minute, unclaimed protected party rewards going to the designated leader, and a 12-hour stash expiry. The actual protected-item eligibility/caps, exact timer behavior and world-boss loot policy remain **open**. No change to current gameplay is authorized by this architecture document.

## Accepted transaction/recovery invariants — implementation choices deferred

The principles below are architectural requirements, not a rollout plan. Suggested numeric caps, UI behavior and claim-overflow policy remain explicitly unapproved implementation/gameplay options.

- **Economic transaction boundary:** item pickup/ownership/placement, Shop purchase, exchange/escrow settlement, direct trade, upgrade, and seller-revenue collection each commit all affected monetary and item facts together with the idempotent outcome/receipt. Partial settlement is never exposed. Capacity, custody, prices, revisions and account balances are checked against authoritative state at commit, not inferred from World UI caches.
- **Crash/timeout reconciliation:** after an ambiguous response, look up the original operation and/or reload authoritative state. Never debit/refund/grant a second time with a fresh ID to "fix" uncertainty. A new World may resume only after the C2/C4/C5 in-flight-operation discovery and state-reconciliation barrier ensures **no unresolved previously admitted command can silently invalidate gameplay being resumed**. A single snapshot alone is insufficient while an old admitted command may later commit.
- **Durable versus transient rewards:** ordinary, unclaimed mob drops can disappear with their hosting process; a successfully claimed ItemInstance is committed. Selected protected dungeon loot uses the already-agreed manifest/stash state machine. A boss crash before the manifest commit does not imply the reward was durably promised; don't show the protected loot before that commit.
- **Account-Yang batch correctness:** future cross-process batched income uses a single earning owner/epoch and replay-safe batch IDs (or an equivalent durable protocol). Force a successful settlement before normal process handoff and any spend dependent on that income. If source crashes with uncommitted grinding Yang, only that accepted soft-income window may be lost. No two processes may both flush the same delta.
- **Service outages:** disable or show pending state for operations requiring Economy commit; World combat may continue with its last safe equipment view. Never deliver spendable money or item ownership optimistically in an outage.
- **Claimable shop Yang:** keep the already-agreed separate account revenue ledger. Overflow must **never lose seller earnings or silently exceed wallet bounds**. Allowing a partial claim while leaving the remainder claimable is **one possible later gameplay policy**, not an accepted requirement; specific wallet caps and claim UX remain open.

### Failure checks for later implementation

Race a buyer purchase with seller withdrawal/price edit; fill buyer inventory between request and commit; race two purchases for one UID; lose the seller's claim response after commit; crash World with a claimed item but pending presentation; crash a dungeon host after a manifest commit; restart Economy with an unknown command; retry the same Yang batch after lost acknowledgment. Verify balances, ownership, receipts and revisions remain consistent.

## Implementation and gameplay decisions still open

1. **Transaction groups:** seller/buyer wallet, offer revision, escrow, ItemInstance custody, inventory capacity, fee/revenue and receipt must not partially commit. Shop withdrawal and price editing rules are accepted above. Built-in offer acceptance, bidder funds reservation and negotiated-offer settlement are explicitly **deferred**; direct trade uses its own atomic contract when available.
2. **Ground item claim:** World reserves a transient drop; Economy durably grants its UID exactly once; lost reply and duplicate claim reconcile by stable identity. Define drop expiry while claim is pending and handling of orphaned reservations.
3. **Ground Yang implementation:** batching/controlled loss, atomic spending and handoff reconciliation are accepted above. Still decide exact batching protocol (stable grant/batch IDs or equivalent lease), replay-safe acknowledgment, bound on pending deltas, crash and failed-handoff recovery, and how the UI represents spendable funds before settlement.
4. **Shop sale income:** separately collectable account-level balance and atomic manual claim are accepted above. Still decide wallet maximum/overflow, partial vs full claim, aggregation across market surfaces, UI synchronization and receipt retention.
5. **Dungeon rewards:** implement the accepted solo/party direction only in a later gameplay milestone. Still decide protected drop eligibility/caps, exact one-minute grace semantics, crash-before-manifest vs crash-after-manifest, claim expiry and recovery of live ground drops.
6. **Database adapter:** SQLite local development can keep one writer; PostgreSQL production uses explicit transaction boundaries, row locking/constraints or optimistic checks, conflict retries and idempotent receipts. Do not assume SQLite serialization equals PostgreSQL semantics.
7. **Recovery:** define backup, WAL/transaction replay, receipts, reconciliation and business invariants after an Economy or World crash.

## Failure cases to test later

Double purchase, partial settlement, duplicate pickup/UID, lost commit reply, grant repeated after World crash, two characters spending the same wallet, failed handoff with unflushed Yang, concurrent seller receipt collection.

## Current code / migration

Preserve the accepted [current persistence policy](../persistence-policy.md): immediate critical economy writes and account-wallet pending-delta checkpointing. Future migration must explicitly replace only the pieces that cannot safely span World Processes; no current gameplay behavior is changed by this draft.
