# V4 — corrected Terrain3D persistence and adoption gate

Terrain3D **1.0.2 stable on Godot 4.7.2** passes the corrected Mandate persistence,
headless, Forward+/Vulkan, collision/movement and navigation gates. Our manually
serialized editor-only region-size migration property triggered the earlier
native crashes. They do not establish Terrain3D/Godot incompatibility.

The editor opens the prepared scene with the stable plugin without script/parse
errors. The user reports that the requested sculpt/paint/undo/redo/save/reopen
operations appear to work. Workflow comfort remains unassessed: the user has
not worked with other map editors. This is not a compatibility failure.
No First Region migration, vegetation/scatter or terrain abstraction is added.

## Branch and baseline

- Original local main: 495d8f3f9ebcc020806cc1cca693565c0387d18b (V0–V3 baseline).
- Continuing topic: codex/visual-v4-terrain3d-spike; investigation HEAD was b8439ca.
  Earlier results and historical DLL fingerprints remain in Git history.
- The pre-existing untracked docs/item-drag-runtime-system.pdf is preserved.
- **No merge to main and no push** during the recheck, as originally requested.
  On 2026-10-13 the user authorized local integration of the verified foundation.
  Manual Terrain3D map authoring is deferred; publication is not requested.
- First Region geometry/gameplay and V3 shader remain unchanged.

## Previous false lead

The failed checked-in scene had material, assets, then region_size = 256 on
Terrain3D. The new instructions describe the same issue with 64; the historical
scene in this branch used 256. Both are the same misuse.

Upstream registers that property with PROPERTY_USAGE_EDITOR and setter
change_region_size(). This is a data migration operation, not persistent scene
storage. Calling it during deserialization of incompletely initialized data
triggered the access violation. The earlier small reproducer repeated that setup.
[Pinned upstream implementation](https://github.com/TokisanGames/Terrain3D/blob/v1.0.2-stable/src/terrain_3d.cpp).

Removing that single serialized property lets both previously crashing scenes
exit zero on stable 1.0.2. There is no property-order workaround: the corrected
scene contains no Terrain3D region_size, and normal PackedScene saving omits it.
The loader derives size from the first persisted Terrain3DRegion. No runtime
height reconstruction or delayed material/assets assignment is used for loading.

The earlier rejection is withdrawn. The 1.1.0-dev retest also used the invalid
scene and therefore did not establish development-build incompatibility either.
Archived crash logs under .godot/verification/terrain3d-1.0.2-baseline and the
visual-v4-dev-* logs remain diagnostic history, not current adoption evidence.

## Version, provenance and installation

- Godot: official **4.7.2-stable**, commit
  ed1daf0bf001b61586d9930840f2f1394092c079; no upgrade.
- Terrain3D: **1.0.2-stable**, official
  [release](https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable).
- Renderer/backend: **Forward+ / Vulkan**, Windows x86_64.
- License: MIT, copyright Cory Petkovsek, Roope Palmroos and contributors.
  Notice retained in tools/terrain3d/LICENSE-Terrain3D.txt and installed addon.
- Installer: tools/terrain3d/setup.py, official release archive SHA256
  a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2.
- Executed Windows debug DLL SHA256:
  bf72686a7e1d8d8370ba9ba5eaa70c59375ee2cb5638d63b8942f1ad7d448cda.

The user restored stable before this recheck. No nightly is required. Installation
keeps Windows/Linux x86_64 debug/release binaries and editor source under ignored
addons/terrain_3d. Project settings enable its editor plugin on this topic branch.
CI provisions the pinned dependency before cold import; smoke itself performs no
plugin download. [Official installation](https://terrain3d.readthedocs.io/en/stable/docs/installation.html).

## Confirmed upstream compatibility

The user reports nine package/engine combinations passing upstream tests,
including stable, main nightly and 4.8-updates on Godot 4.7.2. Those are supplied
results; this task did not independently rerun all nine combinations or Godot 4.8.

Local verification copies the supplied .godot/terrain3d_demo into an ignored,
separate project with the stable addon. Original Demo.tscn, saved regions,
material/assets and character are unmodified. Both local gates pass:

- Headless: three saved regions load, raycast succeeds, original character stands
  on terrain; UPSTREAM_DEMO_OK, exit zero.
- Native Windows Forward+/Vulkan: the same checks pass, the demo renders and a
  screenshot is captured; no native crash or shader/script errors.

Logs: .godot/verification/visual-v4-upstream-headless.log and
visual-v4-upstream-native.out.log / .err.log. The copied demo is a reference only,
excluded from runtime, Git and exports.

## Correctly persisted 64×64 prototype

Open source/common/gameplay/maps/terrain3d_spike/terrain_spike.tscn.
It contains NavigationRegion3D, native Terrain3D, external Terrain3DMaterial,
external Terrain3DAssets and a dedicated native data directory. It is not a startup
map. Its region is **64×64 samples at 1 m spacing**, about 64×64 m.

The source generator tools/terrain3d/generate_spike.gd creates a Terrain3DRegion
resource, assigns its own region_size = 64, height/control/color maps, spacing and
location, then saves data/terrain3d_00_00.res through the native region API.
Formulas produce a flat area, 3 m gentle hill, 7 m steep ridge, shallow depression,
authored winding path and graded eastern shore. Regeneration is an explicit reset;
do not run it over manual edits that should be retained.

Four small seamless PBR ImageTexture pairs are grass/dirt/path/rock, with
albedo/height and normal/roughness, fixed analytic grain, mipmaps, UV scale 0.22,
normal depth 0.35, detiling rotation 0.12 and shift 0.15. These are temporary
workflow assets. Painted grass/dirt blends and the path override the autoshader.
Auto base is rock (3), overlay grass (0), slope parameter 4.0: flat areas select
grass and steep areas rock. The colormap gives modest macro variation. No external
texture pack or legacy source assets are required.

The normal free_editor_textures option is false for this tiny authoring spike,
retaining the four texture asset references for inspection and another save.
The default true option frees runtime editor texture references after uploading
GPU arrays; saving that runtime copy as editor assets would lose the references.
No material/asset is dynamically reassigned after initialization.
[Region API](https://terrain3d.readthedocs.io/en/stable/api/class_terrain3dregion.html).

## Persistence, headless and production movement

The required sequence is verified with separate Godot processes:

1. Create/save region, external material and assets, then close the generator.
2. Cold-load the normal saved scene. Verify get_region_size()==64, one region,
   its own persisted size, saved height, external paths and four material layers.
3. Raycast native collision against saved height. Production PlayerActor3D stands
   and walks on flat ground, uphill and downhill, with feet tracking authored
   height. Its movement implementation is unchanged.
4. Save region, material/assets and normal PackedScene again. SceneState contains
   no editor-only region_size migration property. Close that process.
5. Cold-start again and repeat the same checks.

Both emit TERRAIN_PERSIST_OK and exit zero. Native runtime adds rendered surface,
materials and production movement evidence with TERRAIN_RUNTIME_OK on actual
Forward+/Vulkan. No Terrain3D native, shader compilation or script errors appear
in the corrected runtime gates. Generic Windows certificate and inherited
ObjectDB/resource shutdown diagnostics remain separate from these markers.

Collision is Full/Game on layers 1+16, used by production player/mob bodies.
Headless disables only the camera/clipmap snapping process after full collision
initialization. The same persisted native data and collider remain active and
are checked by raycasts/movement. No fake server camera, separate collider or
server bake representation is introduced. Local preview reuses production actors
and orbit rig; it is a standalone authoring preview, not a new network slice.

## Navigation and V3 shore

After persistence/collision passed, bake_spike_navigation.gd used the existing
Godot source/bake pipeline plus native Terrain3D navigable faces. Saved
navigation.res has **484 polygons** from **5260 source triangles**. Radius 0.5,
height 1.2, climb 0.2, slope 45 degrees, cells 0.125×0.1 match the existing bake.
This prototype's navigation map uses matching precision before region attachment.

validate_navigation.gd waits for actual path availability, then verifies flat
terrain → gentle hill, exclusion of a steep slope, a path stopping before the
submerged shore, and MobActor3D physically following the route. It emits
TERRAIN_NAV_OK, exit zero. Production AI/pathing ownership is unchanged. After
sculpting, rebake through Terrain3D's menu or the narrow helper, rather than the
ordinary NavigationRegion bake alone.
[Upstream navigation](https://terrain3d.readthedocs.io/en/stable/docs/navigation.html).

V3 water is reused unchanged on an eastern plane at y=-0.5. Terrain supplies
submerged depth; the native shore capture shows the graded edge, depth color and
intersection foam. This is compatibility review, not final shoreline art or
swimming. The original First Region water remains unchanged.

## Editor workflow — user-reported functional acceptance

Stable plugin is enabled. Editor open/reopen of the persisted scene passes with
writable local editor settings and no script/parse errors. External material/assets
and CPU texture references remain editable. The requested manual test was:

1. Open the scene and select Navigation/Terrain. Regions → Region Size should be
   **64**; leave that migration control unchanged for this test.
2. Raise a small patch, Lower part, then Smooth its edge. Inspect several angles.
3. Select Grass, Dirt, Path and Rock in the asset dock. Paint a patch/path; use
   Spray Texture to blend an edge. Switching materials should update the brush.
4. Undo/Redo both height and paint changes. Check actual state/viewport changes,
   not only the visual brush decal.
5. Save scene and terrain data (Ctrl+S), close the editor, reopen the same scene,
   confirm height and painting survived, then continue editing and save again.
6. Run F6. WASD uses production movement; RMB orbits; wheel zooms. Check standing
   and walking on edited ground. Rebake navigation after terrain changes.
7. Report any broken operation and whether the workflow is comfortable for maps.

User feedback: "Wszystko wygląda że działa, czy jest wygodne to nie wiem,
nie pracowałem w edytorach mmapy". Record this as user-reported functional
acceptance of the requested editor operations, not independent observation of
each interaction. Comfort will be assessed while authoring a first small map
section. The user's saved terrain edits are preserved; do not regenerate them.
No mouse-coordinate sculpting automation was used.
[Painting reference](https://terrain3d.readthedocs.io/en/stable/docs/texture_painting.html).

## Performance and regression evidence

Initial corrected native overview: 1280×720, RTX 4070, stable addon, six LODs,
mesh size 32, four 256×256 PBR layers, V2 reference 15:30, V3 water, no foliage.
GPU median **1.320 ms**, p95 **1.450 ms**, 120 frames. These are short viewport
observations, not a target-device/soak benchmark or 64-vs-256 comparison.
Final read-only verification after the user's editor save, corrected automatic
grass/rock selection and navigation precision also passes persistence/movement,
navigation and native rendering. Latest capture: GPU median **1.530 ms**,
p95 **1.910 ms**, 120 frames. Logs: visual-v4-manual-persist.log,
visual-v4-manual-nav.log, visual-v4-manual-native.out.log / .err.log.
These checks do not resave or regenerate terrain. Temporary procedural textures
remain visibly repetitive; this spike establishes workflow, not finished art.
Captures and GPU JSON remain ignored under .godot/verification/visual-v4-64-*.

- Default smoke and 74 Web UI contracts: PASS.
- Existing First Region navigation/spawn/shore contract: PASS.
- Windows, ServerWindows and ServerUbuntu resource-pack checks: PASS; applicable
  Windows/headless pack boots PASS. The previous export crash is gone.
- Corrected terrain and local upstream demo: PASS on Forward+/Vulkan.
- Two cold reloads, normal second save, native collision/movement: PASS.
- Terrain navigation bake, slope/shore and production mob traversal: PASS.
- Editor scene loading with stable plugin: PASS. Manual editor operations:
  user-reported PASS; workflow comfort remains unassessed.

The user reports external Linux/headless compatibility. Local WSL still cannot
start (HCS_E_HYPERV_NOT_INSTALLED); resource-pack validation is not a local Linux
execution claim. Accounts/runtime stores and existing user servers are untouched.
Native addon payload and reference demo remain ignored.
The manual editor session also resaved unrelated gameplay/water resources and
project settings. Those changes are preserved outside this corrective commit;
only the Terrain3D plugin enablement is staged from the mixed project settings.

## Adoption result

Technical recommendation: **Godot 4.7.2 + Terrain3D 1.0.2 stable**, pinned by
installer checksum. The previous incompatibility rejection is withdrawn.
Technical gates and the user's functional editor test support adoption. Assess
comfort during the first small authoring exercise. The 2026-10-13 follow-up
authorizes a local no-ff merge of this foundation into main. First Region terrain
authoring/migration remains deferred manual work. Next stages are V5 vegetation
and world dressing, V7 night dressing/local atmosphere, then V8 color grading
and polish, as recorded in project-direction.md.

ADOPT TERRAIN3D WITH PINNED VERSION
