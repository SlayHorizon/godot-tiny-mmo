# Warrior compatibility spike

This extends the optional local visual policy to one player and one weapon.
No original or derived legacy assets are tracked, exported or required by CI.
The source remains outside the Godot project. There is no batch converter,
generic manifest, armor inventory feature or animation-driven combat change.

## Selected conversion

The classic male Warrior uses warrior_novice.gr2 (body and face), the default
hair/hair_1_1.gr2 and the race's target hair skin warrior_hair_01.dds.
The armor variant uses warrior_nahan.gr2, replacing the base body rather than
overlaying two bodies. Each body GLB contains face, hair, materials, its own
compatible skeleton and all seven clips. Sword 00010.gr2 is a separate rigid
model, with its single-bone rest transform baked into metres before GLB export.

The same BlenderGR2rs revision and Blender 5.1.2 used for the dog succeeded.
Importer scale is 0.01; the export wrapper turns 180 degrees around the original
vertical axis. Godot is Y-up, forward -Z. Idle skin bounds are approximately
0.932 x 1.694 x 0.842 m for base, 0.936 x 1.694 x 0.873 m for armor (X/Y/Z).
The gameplay capsule remains radius 0.35 m, height 1.8 m, with unchanged layers,
movement speed, gravity and snapshot interpolation.

| Selection | Bones | Vertices | Triangles |
| --- | --- | --- | --- |
| warrior | 75 | 2634 | 2496 |
| warrior_armor | 76 | 3452 | 3202 |
| iron_sword | Rigid, no exported skin | 558 | 422 |

The armor's extra bone does not prevent name-based import of the same actions.
Hair is rebound to each body's skeleton. Its only weighted bone is Bip01 Head;
weighted bind poses agree to sub-micrometre precision after scale conversion.
Other unweighted bones in the original hair skeleton differ: blindly comparing
all bones, or retaining another independently animated rig, would be misleading.

Materials use resolved embedded DDS-derived images: face and hair 256 x 256,
body/armor 512 x 512; the sword uses weapon_chogeup_01.dds. Color is sRGB,
roughness 0.85, metallic 0. Hair uses alpha cutout; the body and sword are opaque.
GPU captures verified both bodies, head/hair, armor and sword through all clips.

## Clips and root motion

| Logical state | Source selection | Native duration |
| --- | --- | --- |
| idle | onehand_sword/wait.gr2 | 2.0000 s |
| run | onehand_sword/run.gr2 | 0.6667 s |
| attack_1 | onehand_sword/combo_01.gr2 | 1.0000 s |
| attack_2 | onehand_sword/combo_02.gr2 | 0.9333 s |
| attack_3 | onehand_sword/combo_03.gr2 | 1.0667 s |
| hit | onehand_sword/damage.gr2 | 0.5333 s |
| death | general/dead.gr2 | 2.9667 s |

Idle and run loop. Attacks/hit interrupt presentation, play once, then resume
the current idle/run state. Death cannot be interrupted by attack/hit and holds
its final pose until the existing respawn event. The gameplay weapon remains
equipped through death/respawn; its visual hides on death as in the previous
placeholder presentation. The compatibility gallery keeps it visible so the
hand attachment can also be inspected throughout the death clip.

The skeleton socket is equip_right_hand, not a guessed hand vertex position.
The native skeleton retains a 0.01 scale while the independent sword GLB is
already in metres. The BoneAttachment child compensates by reciprocal parent
scale (100 at normal size). A shared +90-degree rotation around sword-local Z
turns the blade upward in idle. This correction belongs to the sword attachment,
including the procedural sword on an animated rig; it is not baked into each GLB.
Swords follow the local +Y blade convention. The capsule placeholder has no hand
socket and already holds its sword upright, so it keeps its original placement.
No hand translation offset was needed.
Attachment world position is tested against the animated bone for every clip
in both variants, after Godot's deferred skeleton update.

Original attack root ranges include about 0.21/0.51/0.25 m in the original
forward axis; death drops the root vertically by about 0.62 m.
Presentation duplicates animation resources, fixes root X/Z to each clip's
first key and retains vertical bob/rotation. Bone root motion never moves the
gameplay CharacterBody. Dog and Warrior share only this small preparation helper.

The original clip durations exceed the current server's 450/450/700 ms combo
recovery. This spike deliberately leaves them at native speed: the next existing
swing event can interrupt a preceding clip. The server's 120/140/180 ms impacts,
combo recovery, hitboxes, damage and persistence are unchanged. Exact animation
contact alignment and retiming remain a later combat presentation pass; native
clip compatibility is proved here without making clips authoritative.

## Local workflow and preview

Use the same ignored tools/dev_assets/local.json and external generated root
described in local-dev-visuals.md. Stage each selection explicitly:

    python tools/dev_assets/stage_asset.py warrior
    python tools/dev_assets/stage_asset.py warrior_armor
    python tools/dev_assets/stage_asset.py iron_sword

Only these three GLBs are copied, to dev_assets/legacy/players/warrior and
dev_assets/legacy/weapons/iron_sword. Godot may create adjacent embedded textures
and import metadata; those stay ignored with the source GLBs.

Open Godot to import new files. The existing prototype player automatically
resolves the logical warrior visual, and its existing equipment event resolves
iron_sword. Armor is a tested presentation variant, selectable in the gallery;
this does not add armor equipment or change player stats.

    & .\tests\run-warrior.ps1
    & .\tests\run-warrior.ps1 -Preview
    & .\tests\run-visuals.ps1 -WithExport

Gallery controls: 1 idle, 2 run, 3/4/5 attacks 1/2/3, 6 hit, 7 death,
V swaps body variants, Escape closes. Pressing a clip key plays it at native
speed. The gallery uses presentation nodes without networking or combat.

For reproducible GPU captures:

    & .\.godot\Godot_v4.7.2-stable_win64_console.exe --path . --mode=client res://tests/warrior_compatibility.tscn --resolution 1280x800 -- --require-dev --capture

Captures go only into ignored .godot/verification/warrior-*.png.
The external selected converter is export_warrior.py in the local spike tools;
its two arguments are the external unpacked pack directory and generated root.

## Verification boundaries

Tests cover both rigs, embedded materials, seven clips, loop policy, skeleton
root tracks, animated hand attachment, variant replacement, existing player
event hooks, unchanged collider, equipment and position, death/respawn, live
body/sword deletion and restaging, and tracked placeholder fallback.

run-visuals.ps1 also runs the Warrior test while the entire local legacy staging
directory is temporarily absent. Its export probe verifies all tracked
placeholders and rejects legacy GLBs, extracted textures and local configuration
inside the Windows PCK. Verification CI runs the no-assets Warrior test without exporting.

Local Godot verification is 4.7.2, including GPU rendering, all existing gameplay
checks and a cold copy from the Git index with no dev_assets. Remote verification CI has not been run here; it now selects Godot 4.7.2.
The former Godot 4.6.3 release workflow was removed. The previously documented baseline
cold-import and shutdown cleanup diagnostics also apply to this spike.
