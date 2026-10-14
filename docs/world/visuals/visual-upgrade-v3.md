# Visual V3 — First Region water

The former solid-color water box is replaced by a custom `spatial` shader on a
Godot `ShaderMaterial`. It lives in `source/client/world_visuals/water`; there is
no water plugin. The existing 22×144 m channel and shoreline collision remain.
Water and its submerged visual bed are omitted on server/headless worlds.
Swimming and gameplay effects remain outside this presentation milestone.

## Surface and lighting

The surface is a 44×288-cell PlaneMesh (25,344 triangles) with three analytic
Gerstner waves: wavelengths 7 / 3.8 / 2.2 m, amplitudes 4.5 / 2.5 / 1.2 cm.
Analytic derivatives provide the large-wave normal. A minimal submerged slope
supplies actual depth: from the narrow intersection at the existing boundary
to roughly 3.2 m below the surface. It is visual geometry without collision,
not a coastline/terrain reconstruction. The existing beach and boundary box
are still deliberately graybox geometry.

The shader reconstructs view/world positions from the current viewport's
reverse-Z depth buffer. Depth absorption transitions from lighter shallow water
to dark cool deep water. Dielectric Fresnel reduces transmission at grazing
angles; Godot's environment radiance supplies the reflected V2 sky. Its GGX
lighting supplies actual sun/moon color, energy and direction, without a second
water-specific clock or fabricated highlight.

Two independently moving UV layers sample a seamless procedural normal map
(NoiseTexture2D/FastNoiseLite, fixed seed, normal conversion, mipmaps and
anisotropic filtering). Detail fades over 18–70 m; roughness increases in the
distance. Screen refraction is subtle (0.003 UV scale), fades in shallow water
and rejects displaced taps containing foreground geometry. Transmission uses
the already-lit screen color without multiplying by scene lighting a second
time. A noise-broken depth-intersection band adds modest shoreline foam.
Crest foam and SSR remain disabled/deferred; the current sky reflection is
sufficient for this pass. No planar reflection, FFT ocean, player-driven waves,
global caustics, fluid simulation or underwater volume is introduced.

`region_water_material.tres` holds the authored material and normal-map resource;
the shader exposes colors, absorption, wave/detail/refraction/foam strengths and
detail fade distance. Surface motion uses real elapsed presentation seconds,
independently of the accelerated world calendar. V2 controls lighting normally.

Depth and shader API references:
[Godot reverse-Z reconstruction](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html),
[Godot spatial shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).

## Native acceptance and verification

```powershell
git diff --check
& ./tests/run-smoke.ps1 -NodeExecutable '<Node executable>'
& ./tests/run-first-region.ps1
& ./tests/run-visual-v0.ps1 -Scene visual_v3 -RenderingMethod forward_plus
& ./tests/run-cef-export.ps1
python ./tools/encode-visual-timelapse.py .godot/verification/visual-v3-water-motion .godot/verification/visual-v3-sunset-motion.gif
python ./tools/encode-visual-timelapse.py .godot/verification/visual-v3-distant-motion .godot/verification/visual-v3-distant-motion.gif
python ./tools/encode-visual-timelapse.py .godot/verification/visual-v3-gameplay-motion .godot/verification/visual-v3-gameplay-motion.gif
```

GIF encoding optionally requires Pillow. The native runner uses port 18098;
run it sequentially with other PvE/network fixtures. Export checks need Node
available on PATH.

The native fixture shares the actual First Region World3D in a review viewport.
It compares the old material/box with the new surface at identical cameras and
V2 hours: 14:00 day, overhead depth view, 18:30 sunset, midnight and distant view.
It also captures the base waves/depth/Fresnel without normal/refraction/foam,
and a full-moon date with the camera aligned for the real moon highlight.
Animated sunset, distant and production-camera sequences support visual review.
The production camera sequence uses the actual orbit rig with default zoom/pitch
and a valid shoreline target; it does not add player-facing preview controls.

Native review confirms moving surface, shallow/deep distinction, grazing sky
reflection, warm sunset specular, cool moon specular and broken intersection foam.
Distance review retains broad waves while fine ripple detail fades; no obvious
moire is observed in these captured views. This is local visual evidence, not
a guarantee for every camera/resolution. There are no pixel snapshot assertions.
The milestone fixture checks rendered composition/server omission and rejects
shader/script compilation errors, while reusing the complete CEF synthetic input,
lifecycle, drag, Shop, Upgrade and confirmed combat pass. Existing headless tests
cannot establish depth/screen sampling or native temporal appearance.

Default smoke (including 74 Web UI contracts), First Region navigation/shore
collision, native V3/CEF and Windows/ServerWindows/ServerUbuntu resource-pack
checks pass. The shoreline ray remains blocked, preserving the visual-only water
boundary. Export checks establish resources and headless boots, not full release
executable behavior. Physical input/DPI/alt-tab and an authenticated route
playtest remain separate from this native fixture.

Ignored captures/logs/GPU JSON/GIFs are under `.godot/verification/visual-v3-*`.
Paired GPU measurements use the same 1280×720 day review viewport, 90 frames per
material, on RTX 4070: old box median **1.203 ms** / p95 **1.498 ms**, new water
median **1.364 ms** / p95 **1.843 ms** (median difference **+0.161 ms**).
They describe a short local sample with the main viewport
also rendering; they exclude CEF GPU work and are not a soak/target-device budget.
Optional local character/UI assets remain ignored and outside production exports.

V4 can address boxy shoreline geometry, terrain transitions and final world art.
