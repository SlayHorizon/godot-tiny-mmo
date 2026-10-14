# Accepted decisions and unresolved product choices

## Active decisions

- [Project direction](project-direction.md): current gameplay, presentation and development priorities.
- [Economy C1–C5](../architecture/economy/README.md): accepted **architectural** decisions for a shared realm economy.
- [Dynamic channels, dungeons and World topology](../architecture/world-instance-architecture.md): accepted future architecture, not yet deployed.
- [Marketplace UX and contract gap](marketplace-v2-gaps.md): current `shop` behavior versus approved future Store/Listing behavior. Do **not** mistake a target feature for code already shipped.
- [Gameplay direction](gameplay-direction.md): consolidated goals and explicitly deferred balancing ideas; older incompatible channel assumptions have been removed.

## Decision precedence

The source code and [persistence policy](../architecture/persistence-policy.md) describe current behavior. Newer accepted domain contracts describe desired future behavior; design **does not override the running code without an implementation PR**. Archived records and experimental plans explain why a decision was made but are not current implementation instructions.

For an architecture change, link the relevant accepted rule, the concrete behavior being changed, the regression/failure tests, and any data migration. Track still-open product choices as open rather than inventing defaults.
