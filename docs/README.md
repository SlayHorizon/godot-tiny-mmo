# Mandate of Three — documentation map

**Start here.** This index distinguishes the **current implementation**, **accepted future architecture**, **product decisions**, **upcoming work**, and **historical evidence**. The distinction matters: an accepted contract does not mean the distributed service already exists.

| Area | Where to go | How to read it |
| --- | --- | --- |
| Architecture | [Architecture index](architecture/README.md) | Target boundaries, invariants and present persistence policy |
| Decisions | [Decision index](decisions/README.md) | Accepted direction and decisions not yet implemented |
| Implemented | [Implementation index](implemented/README.md) | What is verified on `main` versus still only on `shop` |
| Plans | [Plan index](plans/README.md) | Ordered pre-alpha hardening and feature work |
| History | [Historical records](history/README.md) | Superseded snapshots and dated investigations |
| Evidence | [Evidence index](evidence/README.md) | Recorded measurements, CI and reproducibility limits |

## Canonical current documents

- [Project direction](decisions/project-direction.md) — gameplay/current milestone direction; see [architecture hardening plan](plans/architecture-hardening.md) for the newer pre-alpha technical work sequence.
- [Persistence policy](architecture/persistence-policy.md) — **actual single-World + SQLite** checkpoint and transaction behavior.
- [Testing policy](development/testing.md) and [CI](development/ci.md) — what checks prove and what still requires native testing.
- [Economy V2 C1–C5](architecture/economy/README.md) — accepted **future** realm-wide Economy contracts; no distributed implementation yet.
- [Dynamic World/CH architecture](architecture/world-instance-architecture.md) — accepted design for MapInstances, CH and host processes; implementation deferred.
- [Marketplace policy gaps](decisions/marketplace-v2-gaps.md) — approved UX changes that **are not implemented** by the existing `shop` branch.
- [Marketplace/Auction PR #1](https://github.com/PatrykCieszynski/Mandate-of-Three/pull/1) — open integration PR at the time this index was written. Auction PR #2 is merged **into `shop`**, not into `main`.

## File-by-file retention review

Before deleting legacy Markdown or collapsing reports, see the [complete documentation audit](plans/documentation-file-audit.md). It covers every file currently on `main` and the additional docs/evidence on the open `shop` branch, with an explicit keep/consolidate/delete recommendation per file. Proposed removals are **not yet applied**; preserve links and unique evidence when executing the cleanup.

## How to maintain this index

1. Mark **implemented**, **accepted design**, **proposed**, or **historical** explicitly; never equate a merged design document with finished code.
2. When a decision changes, update its canonical decision/contract and add a link to the superseded history rather than silently altering old measurements.
3. A plan is not a new implementation authorization by itself. Keep changes on separate topic branches and preserve the repository's testing/merge workflow.
4. Many established links still target older files directly under `docs/`. This index organizes them **without moving or deleting them** while Marketplace PR #1 is in flight. Once `shop` is merged, a separate verified link/move sweep can physically relocate old documents without broken references.
