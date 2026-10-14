# Visual V1 — Sky, Sun and Lighting baseline

Integrated on 2026-10-12 for the native Forward+ / Vulkan client. One reference
look is used: **15:30 on a summer day**. Sky3D's game/editor clocks are disabled,
system-clock synchronization is off, and no gameplay WorldTime is introduced.
Clouds drift slowly while sun angle, exposure and atmosphere remain fixed.

## Composition and dependency

`GameWorld3D` replaces its old directional light + solid background/flat ambient
with `source/client/world_visuals/world_visual_environment.tscn` on non-headless
clients. The authored scene is a Sky3D WorldEnvironment containing SunLight,
MoonLight, SkyDome and TimeOfDay. Sky3D controls the sun's transform, color and
energy; tune these through SkyDome/TimeOfDay rather than overriding its light
each frame. Server/headless instances create none of these nodes.

[Sky3D v2.1.0](https://github.com/TokisanGames/Sky3D/releases/tag/v2.1.0) is vendored
under `addons/sky_3d`, pinned to commit `6e151bc3d941906643443b3751a1df545a08feda`.
Upstream script/shader behavior and image bytes are unchanged; trailing whitespace
is normalized for repository checks, and Godot regenerates texture import
metadata for our compression settings. The plugin is enabled for editor
configuration. No demo/project/reference assets outside the addon are copied.
MIT and third-party notices remain alongside the source/assets; see
[provenance](../addons/sky_3d/UPSTREAM.md) and [credits](third-party-credits.md).

The scene's Environment, Sky, ShaderMaterial and CameraAttributes are local to
each instantiated scene, since Sky3D mutates these resources during setup.
There is one world environment and one lit directional sun, not a retained old
light illuminating the scene a second time. Moon energy is zero in this preset.

## Authored reference settings

| Area | Baseline |
| --- | --- |
| Reference time | 15:30, 2025-06-21, latitude 35°, longitude/UTC 0; clock stopped |
| Sky | Procedural Sky3D scattering, blue zenith/light horizon, native sky shader |
| Clouds | Cumulus coverage 0.42/intensity 0.75, cirrus coverage 0.25, slow wind 0.4 |
| Sun | SkyDome energy 1.65, warm-white daylight, warmer horizon tint |
| Ambient / reflections | Both from sky, sky contribution 1.0, 256px radiance |
| Tonemapping / exposure | AgX; tone exposure 1.05; camera multiplier 1.0; auto exposure off |
| Shadows | 4096 directional atlas, blended cascades, 100m distance, bias 0.03 / normal bias 1.0 |
| SSAO | Radius 0.85, intensity 0.7, power 1.3, detail 0.25 |
| SSIL | Radius 1.5, intensity 0.12 |
| Fog / haze | Native Environment fog, density 0.0018, aerial perspective 0.6, sky affect 0.25 |

Sky3D's extra screen-space fog is disabled. Native fog provides a single subtle
distance/horizon haze, rather than stacking two fog passes. No volumetric fog,
LUT, terrain/water/vegetation plugin, new asset dressing or full day/night cycle
is added. Exposure is deliberately fixed to make this first lighting pass stable.

## Native review and regression evidence

From the repository root, with the pinned CEF addon already installed/imported:

```powershell
& .\tests\run-visual-v0.ps1 -RenderingMethod forward_plus -Scene visual_v1
```

This reuses V0's one disposable headless world/native client fixture on port
18098. It performs the actual CEF/input/drag/orbit/reload/resize/recreate/Shop/
Upgrade and confirmed combat checks, then shares the live World3D with a separate
1280×720 review SubViewport. The review does not alter the gameplay camera/CEF UI.
For each hub, region, outskirts and horizon view it alternates the former V0
environment/light and the new V1 environment/light with the same geometry/camera.
Both comparisons use the current shadow atlas. Clouds are stopped only during
the captures; actor idle poses can advance. Local CombatTraceDebug overlays are
hidden for these review images and restored without changing the user's toggle.

The native fixture checks that 15:30 remains fixed across the rendered review,
that Sky3D/AgX and the real shadow-casting sun are active, and that the headless
server omits WorldVisualEnvironment. These checks protect the new static-time
and presentation-only composition contracts. Existing headless/Node suites
cannot establish the rendered sky, exposure, shadows or CEF accelerated path.
No pixel baselines or exact animation/frame-time assertions are added to smoke.

Results on Godot 4.7.2, godot-cef v2.0.0, Windows x64, RTX 4070:

- Native V1 environment review and complete inherited V0 pass: PASS, exits zero.
- CEF accelerated OSR remains supported; native surface is Texture2DRD.
- Default smoke and all 74 Web UI contracts: PASS.
- Existing Windows client / ServerWindows / ServerUbuntu resource-pack boundary
  checks and applicable headless pack boots: PASS. Exported servers omit CEF.
- No surviving Godot/CEF processes observed after the completed checks.

Ignored images, JSON and fixed-name logs are under `.godot/verification/visual-v1-*`.
The useful image pairs are `hub`, `region`, `outskirts` and `horizon`, suffixed
`before` / `after`. Current captures include optional local development character
assets; no derived legacy images/models enter Git or exports.

The final 3-second game-viewport sample (after review viewport removal) measured
GPU median **1.600 ms**, GPU p95 **1.919 ms**, frame median **6.944 ms**, frame p95
**9.091 ms**, 398 frames. VSync is enabled. This is a short local observation;
viewport timing excludes CEF GPU work and is not a target-device or soak benchmark.

Physical mouse/keyboard, alt-tab/DPI/IME and a normal authenticated route playtest
remain separate. Resource-pack verification is not a full distributable native
executable. Existing inherited ObjectDB/resource shutdown warnings remain.

## Next tuning

V2 is now integrated as a separate [world-time milestone](visual-upgrade-v2.md).
Production lighting follows the server calendar; the V1 native review temporarily
freezes its 15:30 reference and restores the live clock afterwards. The results
above describe the original V1 milestone.

First Region's colored ground planes, water strip, block buildings and map
boundary remain graybox geometry; sky/lighting cannot replace their later
art/material pass. Weather remains a separately scoped future milestone.
