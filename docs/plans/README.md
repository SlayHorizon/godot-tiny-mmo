# Active plans and work packages

**Documentation cleanup:** [File-by-file audit of `main` and `shop`](documentation-file-audit.md) — separate approved deletion/consolidation pass after review. This is not an automatic deletion instruction.

**Current technical priority:** [Pre-alpha architecture hardening and Auction integration](architecture-hardening.md) — ordered, testable PRs for authentication, RPC boundaries, Marketplace, persistence and World synchronization.

**Gameplay / visuals:** [Project direction](../decisions/project-direction.md), [first region](../world/first-region-graybox.md), [Visual V4 Terrain3D](../world/visuals/visual-upgrade-v4-terrain3d.md), [Warrior feel](../gameplay/combat/warrior-action-polish.md).

**Completed spike plans** were removed from the active documentation tree; use Git history only if implementation provenance is needed. Do not restore their old TODO lists.

Treat accepted Economy/World ADRs as target behavior, not as a reason to extract a distributed service before a measurable need. New changes require a concrete contract and relevant regression checks.
