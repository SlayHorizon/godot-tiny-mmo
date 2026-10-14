# Accepted project direction

Current policy as of 2026-10-13. This file describes accepted scope and next work;
[decision history](history/project-direction-2026-10-09.md) records prior stages.

## Keep the technical foundation small

Tiny MMO supplies gateway/master/world, auth/sessions, instance lifecycle,
transport/replication and persistence. Preserve these working systems. Open-MT2
is a behavioral reference, not a dependency or runtime.

Movement, combat and pickup are server-authoritative. Clients send intentions;
server validates input, ownership, revisions, placement and economic operations.
The existing ItemDefinition/ItemInstance model is sufficient: UID, owner,
placement, upgrade level, affixes, sockets and revision. Do not build speculative
stat, crafting or persistence frameworks.

## Working vertical slice

- Server-side 3D movement/physics and remote interpolation.
- Directional melee against multiple targets, data-defined Warrior 4/5/6-hit combo, baked Warrior melee trace with cone fallback,
  final knockdown/get-up with profile-scaled physical displacement,
  data-defined mixed mob packs with cheap straight-line AI, hit reactions, death and respawn. Targets only assist
  autoattack/future skills. Balance is deferred.
- Ground item loot, reservation, pickup, transactional inventory/equipment and
  runtime combat stats. Combat does not query SQLite per swing.
- XP/levels in RAM, dirty checkpoints around 60 seconds and forced session saves.
- Yang ground currency, short-range autoloot without a pet, runtime wallet,
  pending income deltas/checkpoints around 30 seconds and one atomic test spend.

[Persistence policy](persistence-policy.md) is authoritative: soft progression
uses checkpoints; unique items and critical economy changes commit atomically
and immediately. Do not batch item pickup/equip/trade/upgrade with XP.

## Current UI and development workflow

Windows CEF UI targets Vulkan Forward+ after the [Visual V0 native pass](visual-upgrade-v0.md).
Mobile remains a tested comparison option. Compatibility/OpenGL is unsupported /
best-effort. Pinned CEF is installed under `addons/godot_cef`; the client runs
the root project, with no copied gameplay tree. Exported servers omit CEF;
local headless may load the extension but must not create a browser/subprocess.
See [CEF integration](cef-addon-integration.md) and [Web UI boundary](web-ui.md).

The production Web Inventory is five columns × nine rows × four pages, with
1×1/1×2/1×3 footprints, no rotation, logical 40px slots and a fixed draggable,
clamped window. Click-to-carry and drag/drop send authoritative move intentions.
Schema v15 migrates old anchors atomically while preserving unique items.
Individual extracted legacy PNGs are temporary local skin, isolated behind
semantic names. Follow [UI Contract v1](ui-contract.md).

Production Inventory and the weapon Equipment window compose the small internal
[Core UI](core-ui.md). Shared shell/chrome, semantic skins and separate UI/item icon
resolvers reduce repeated window code. Domain state and actions remain in screens;
Account Storage (15×9×2) is integrated through the same CEF bridge; B opens it,
with server-authoritative atomic deposit/withdrawal and account access.
The neutral NPC foundation now exposes data-defined services through an
interactive development Blacksmith: Upgrade and Weapon Shop. Server contexts and
service authorization are map/range scoped. Shop offers are editable resources;
NPC Shop purchases now atomically receive items and spend persisted/pending Yang.
The CEF Shop supports right-click, exact Inventory drops and automatic receiving;
Upgrade now supports [atomic +0 → +1](npc-upgrade-ui.md), consuming Inventory
material and Yang, with server selection and an Inventory-to-Blacksmith drop entry. See [NPC services](npc-services.md) and
[NPC Shop](npc-shop.md). Global MVP Storage remains available through B.

A full HUD/character sheet and final art remain outside this slice. No frontend framework. Use small headless smoke checks by
default; extended gameplay/asset/export tests are opt-in. Native UI checks belong
at meaningful milestones. See [testing policy](testing.md).

Work on topic branches, inspect/check changes and merge locally with `--no-ff`.
Do not delete quarantined modules/assets without dependency analysis. Legacy save
compatibility is temporary; a deliberate schema reset/migration belongs before
public alpha. Keep existing user data paths during cosmetic project renames.

## Camera presentation slice

[Camera v1](camera-v1.md) adds an independent client orbit/zoom rig with
sphere collision, damped return and data-defined settings. Manual WASD follows the camera on the XZ plane while preserving the existing
bounded intention protocol and server authority. Auto-align is off by default. Native
feel/CEF interaction still require the documented manual acceptance pass.

## Visual baseline

[Visual V1](visual-upgrade-v1.md) establishes the fixed 15:30 Sky3D reference:
procedural atmosphere/clouds, sun, sky ambient/reflections, AgX, directional
shadows, SSAO, light SSIL and native horizon haze. [Visual V2](visual-upgrade-v2.md)
now drives continuous day/night, moon phases and stars from the shared World Server
calendar (96 real minutes per game day), including lighting, exposure and fog.
Weather and terrain conversion remain deferred.
[Visual V3](visual-upgrade-v3.md) replaces the water strip's solid box with a
custom depth/Fresnel/Gerstner ShaderMaterial, fine normals, subtle refraction
and intersection foam. It follows V2 sky/sun/moon lighting; the coastline remains
graybox and swimming is deferred.
The existing First Region graybox and assets remain the basis for visual tuning.
Server/headless composition omits the visual environment nodes.

[Visual V4](visual-upgrade-v4-terrain3d.md) accepts Terrain3D 1.0.2 stable on
Godot 4.7.2, Forward+/Vulkan. The persisted 64x64 prototype, collision/movement,
navigation and editor workflow passed the adoption gate. Integrate the verified
foundation locally; actual First Region terrain authoring remains manual work
for the user and is deferred until they have time. Do not regenerate their saved
terrain edits or treat the workflow spike as a finished map conversion.

Remaining visual work, in the accepted order:

1. V4 Terrain: manually author the intended map with Terrain3D, then integrate it.
2. V5 Vegetation + world dressing.
3. V7 Night dressing + local atmosphere.
4. V8 Final color grading / polish.

These are future stages; vegetation, night dressing and final grading do not
start as part of the V4 foundation merge.

## Next gameplay milestones

Yang wallet/autoloot/test spend, NPC Shop and the +0 → +1 Upgrade slice are
implemented. Upgrade supports Inventory items only, one material, pending Yang
and 100% success. Higher upgrades/failure/destruction remain deferred. Next:

1. [First region graybox](first-region-graybox.md): hub, three combat areas, routes,
   landmarks, camera obstacles, four Metin sites and a water test strip. Implemented;
   scale and travel/combat feel need a manual pass.
2. [Metin Encounter v1](metin-encounter-v1.md): implemented shared stone combat,
   threshold waves, ground rewards and timed respawn. Native loop playtest is next.
3. [Mob packs v1](mob-packs-v1.md): implemented six denser mixed packs, shared aggro,
   anchor leash and per-member replacement. Next is a manual density/combat feel
   pass, then pacing and visuals. No additional AI framework before playtesting.

One affix reroll and the party vertical slice remain planned after this focused
world loop. Regional pressure (kills, threshold, event spawn and reset) remains the
accepted direction for a later event cadence pass, not another framework now.

World direction: one logical world/realm with dynamic, player-visible public channels
provisioned per busy map as the preferred policy; hidden overflow layers stay an
optional routing policy. Public DT-style and private party dungeons share the
MapInstance lifecycle; later, instances may run across a pool of World Processes
and machines while economy remains authoritative per realm. This is a deferred
architecture, not a current refactor: see [world instance ADR](world-instance-architecture.md).
Spawn regions/regional pressure, viable solo and party play, self-sufficient
classes and basic QoL without a consumable tax remain gameplay direction.
Numerical values are balance proposals; see [design decisions](Mandate_of_Three_Design_Decisions.md).

Bosses, free base dungeons, keyed tiers, classes/auras, potions/lure, AOI, local
prediction, layering and PostgreSQL remain later work. For AOI, consider reusing
Tiny MMO's grid on the XZ plane. Further technical cleanup must stay bounded and
must not replace the next gameplay milestone with another large refactor.

[Hit Reactions v1](hit-reactions-v1.md) adds a four-hit basic combo, noninterrupting
flinch and server-authoritative knockdown/get-up with per-mob resistance profiles.
Physical knockback is now separate step data. Final reaction clips and PvP rules
remain later work. [Warrior Combat Feel & Presentation v2](warrior-combat-feel-v2.md)
shares authoritative Attack Speed with playback, buffers one next intent and adds
client-only trails and confirmed feedback. Live combat feel is the next playtest;
no further CombatTrace geometry pass is part of this milestone.
[Warrior basic action polish](warrior-action-polish.md) adds hitch-safe scheduled
resolution, full-motion input locks, data-authored forward advance, presentation
turn blending and local confirmed-finisher camera feedback.

## Selective spike graduation

[Approved graduation plan](spike-graduation-plan.md) separates the old production
slice in three packages. Package A is complete: explicit commit/cache/fan-out,
a narrow injected TinyMMO adapter, kill/ground-loot extraction and architecture
regression checks. Combat retains the existing RPC path and attack/AI behavior.
Package B is locally integrated: combat runtime/services and actor/mob cleanup.
Package C is locally integrated: Core UI command/projector/adapters and composition.
[Graduation cleanup](spike-graduation-cleanup.md) finishes production names/layout
and removes the replaced native UI; [inherited gameplay](inherited-runtime.md)
remains deferred. Native CEF acceptance remains pending.
Packages A/B/C and graduation cleanup are integrated into main on 2026-10-12.
Their topic branches and --no-ff merges preserve each reviewed milestone.
World/persistence P2 decisions remain
deferred as recorded in the plan.
