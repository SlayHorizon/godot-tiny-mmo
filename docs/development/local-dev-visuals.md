# Optional local development visuals

Gameplay uses the logical ID stray_dog. The resolver supports this one mob:

1. res://assets/final/mobs/stray_dog.tscn (tracked Mandate artwork, when supplied).
2. res://dev_assets/legacy/mobs/stray_dog/stray_dog.glb (optional local development).
3. res://assets/placeholders/mobs/stray_dog_placeholder.tscn (tracked procedural dog).

The repository root is the Godot project root. Full legacy source and original
assets remain outside it, for example ../Mandate Local/legacy/{bin,src,extern,generated}.
Only the selected, self-contained converted GLB goes into dev_assets.
Neither original GR2/DDS/TGA nor converted models, textures or materials belong in Git.

## Stage the existing conversion

Use Python 3.12+ on Windows. The tool neither converts nor scans for other assets.

    Copy-Item tools/dev_assets/local.example.json tools/dev_assets/local.json
    # Edit generated_root if your external layout differs.
    python tools/dev_assets/stage_asset.py stray_dog

The example points to ../Mandate Local/legacy/generated, relative to the
repository root. The source is mobs/stray_dog/stray_dog.glb beneath that directory.
Override precedence: --generated-root, MANDATE_LEGACY_GENERATED_ROOT, then local
JSON. The configuration and destination are gitignored.

    python tools/dev_assets/stage_asset.py stray_dog --generated-root 'X:/my-local-assets/generated'

Source directories inside the Godot project are rejected. Staging validates the
GLB container, rejects external texture/buffer references, rejects destination
links/junctions and replaces only the selected file atomically. It does not copy
the full legacy tree. Conversion stays in the external spike workspace.

Open Godot to import a newly staged GLB. Then existing Wild Dogs use it without
content or gameplay changes. Removing dev_assets/legacy changes existing dogs
to the placeholder within 0.25 seconds; stale imported resources cannot revive a
deleted source. Restaging an already imported file restores the optional visual.
A newly converted file must first be imported by the editor.

## Runtime and export boundaries

The local source is enabled only in editor builds of Godot, including running
the project from the editor binary. --no-dev-visuals or
MANDATE_NO_DEV_VISUALS=1 forces a clean local run. Exported debug/release builds
and dedicated-server builds always resolve final artwork or the placeholder.
There is no preload or scene dependency on the local GLB.

All five export presets exclude dev_assets/*, .local/* and local staging
configuration. The existing export plugin also skips these paths. Keep those
exclusions when adding a preset. Verification CI runs the placeholder entity test on
a fresh checkout without exporting; it has no legacy source requirement.

The resolver is deliberately small, with no generic manifest or batch system.
Warrior and Iron Sword now follow the same policy; see [Warrior compatibility](warrior-compatibility.md).

## Animation and compatibility findings

The successfully converted spike is staged unchanged. Import/export settings:
Blender 5.1.2, BlenderGR2rs revision
8722bb1e6fa431cfd395b4e56f8eb2c37b9e05fc, importer scale 0.01 and a
180-degree turn about the original vertical axis before glTF export. Godot is
Y-up; forward is -Z, matching the existing dog body rotation. No compensating
scale or absolute external path is present in gameplay code.

Rest skinned dimensions are approximately 0.360 x 0.965 x 1.227 metres (X/Y/Z).
The mesh's unskinned AABB is not a reliable measure of animated size. GPU renders
confirmed the upright idle/run dog, forward direction, textured skin and death
pose. The collider remains the original capsule, radius 0.4 m and height 0.8 m.

The skin has 38 bones, 682 vertices and 924 triangles. All vertices are weighted;
29 bones have weights. Godot renames the root bone to Bip01_2 because the
armature object is also named Bip01; presentation identifies roots by hierarchy,
not that name. The embedded 512 x 512 albedo comes from the DDS conversion, uses
sRGB and opaque PBR, roughness 0.85 and metallic 0.

| State | Clip duration | Presentation trigger |
| --- | --- | --- |
| idle | 2.3333 s | Stationary live dog |
| run | 0.5000 s | Movement from existing snapshot interpolation |
| attack | 0.9333 s | Existing authoritative ATTACK state |
| hit | 0.8333 s | Existing hit presentation event |
| death | 0.8333 s | Transition to DEAD |

Idle/run/attack loop. Hit is a one-shot, then resumes the current movement state.
Death plays once and hides the visual after one second; repeated DEAD snapshots
do not restart it. Respawn restores the visual. Placeholder hit/death use a
small scale flash and tip-over effect.

Original attack and death clips include horizontal skeletal root displacement
(up to about 1.10 m transient attack displacement and 1.32 m death endpoint
displacement). Presentation duplicates each animation resource per dog and
freezes root position X/Z at its first key. Vertical bob and root rotation are
retained. The gameplay body never receives animation root motion. This also
prevents animations walking the visual away from its collider.

Clip timing does not schedule damage or gameplay transitions. Attack is a visual
loop while the existing AI says ATTACK; it is not synchronized to each server
damage tick. AI, navigation, HP, loot, networking, collision, death timers and
persistence remain authoritative and independent of selected artwork.

## Verification

    python tests/test_asset_staging.py
    & .\tests\run-visuals.ps1
    & .\tests\run-visuals.ps1 -WithExport

WithExport also exports a Windows PCK and mounts it in an isolated probe project,
checking that the placeholder ships and the local GLB/configuration do not.
run-visuals.ps1 verifies final priority, development suppression and no-assets
fallback. With the selected GLB imported it also checks skeleton, material,
five clips, in-place root tracks and live removal/restaging. It temporarily
moves the local directory within .godot/verification and restores it in
finally; do not run concurrent staging/imports during that test. It refuses
to overwrite existing final artwork.

Verified locally on Godot 4.7.2: staging tests, all visual modes, live fallback,
GPU rendering, Windows PCK contents, a cold project copied only from the Git
index, and the existing item/spike3d/PvE/combat/progression/XP/Yang checks.
Remote CI has not been run. The former Godot 4.6.3 release workflow was removed;
current verification CI selects Godot 4.7.2. Existing headless tests
and editor exports report resource/ObjectDB cleanup warnings at process exit;
the visual tests have the same three-resource warning, with successful markers.


On a completely empty import cache, the first import logs missing generated
translation files and an upstream UI theme texture before those files are
imported. The same messages were reproduced from unchanged main. Reopening
after import has no missing-resource/parse errors. No legacy asset is involved.
This existing cold-import limitation is not silently counted as a clean first
import.

External batch-conversion history: [legacy pipeline](legacy-asset-pipeline.md).
The in-repository converter has been removed. stage_asset.py remains available
for the four original selected IDs.
