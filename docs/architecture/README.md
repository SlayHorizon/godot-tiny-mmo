# Architecture — ownership and constraints

## Accepted target architecture (not yet implemented)

- [Economy V2 — contracts C1–C5](economy/README.md): account Yang, ItemInstance custody, idempotent transactions, snapshots, session fencing and CH handoff.
- [World instance topology and dynamic channels](world-instance-architecture.md): MapInstance lifecycle, pooling, public/party dungeons, visible channels and optional overflow layers.

These documents intentionally distinguish **one logical authority** from **one physical process**. In the near term we can enforce good internal module boundaries inside the current World without immediately deploying PostgreSQL or splitting processes.

## Running prototype contracts

- [Persistence and crash window](persistence-policy.md): SQLite writer, wallet pending deltas, dirty XP checkpoints and immediate critical Item/Yang COMMIT.
- [Server/client/Web UI boundary](../ui/web-ui.md): authoritative gameplay, explicit CEF commands, snapshots.
- [Items and identity](item-instances.md) and [Yang wallet](yang-wallet.md).
- [Current test contracts](../development/testing.md).

**Authority rule:** where target contracts differ from the running prototype, the current persistence policy describes reality; accepted Economy/World ADRs describe future desired behavior. The [implementation plan](../plans/architecture-hardening.md) bridges them in testable packages.
