# Visual V2 — World time, day/night, moon and stars

V2 replaces the stopped V1 reference hour with a shared World Server calendar.
First Region now transitions continuously through dawn, daytime, sunset and night
on the native Forward+/Vulkan client. Sky3D remains the celestial/sky renderer;
the new wrapper owns the authored lighting profile. Geometry and materials remain
the existing graybox. Weather and a gameplay calendar/event framework are deferred.

## Authoritative calendar

`WorldServer.world_time` derives calendar seconds from the shared resource
`source/common/gameplay/world_time/world_time_settings.tres`. One game day lasts
**96 real minutes** (15 game seconds per real second). The real epoch is
2026-10-12 12:00 UTC; its game epoch is 2025-06-21 15:30. These are fixed anchors,
not a start-at-15:30 reset on every login. Changing the rate also changes the
calendar calculated from those anchors; edit both anchors when deliberately
establishing a new calendar reference.

The server samples UTC at construction, then advances from monotonic ticks.
Restart reconstructs the ongoing calendar from the epoch; maps in a World Server
share its clock. Separate hosts need consistent system UTC for the same phase.
There are no tick/checkpoint database writes. Combat, respawn, loot expiry,
progression checkpoints and item/economy transactions keep their existing clocks
and persistence rules.

The authenticated map path sends an authority-only sample on entry and every
five seconds. Clients extrapolate and smoothly correct absolute calendar seconds,
including midnight/date rollover, reject malformed/stale samples, and cannot run
backwards during delayed correction. No client time-setting RPC is exposed.
This is presentation synchronization with transport delay, not precision clock
alignment or a general scheduling service.

## Lighting and authoring

`source/client/world_visuals/world_visual_environment.gd` feeds fractional calendar
hours and the date into Sky3D. Its existing celestial calculations animate sun
altitude/azimuth, sun color, moon position/texture phase and star orientation.
Six editable curves and two gradients in the environment scene continuously
control sun energy, ambient energy, sky contribution, exposure, fog density/light
energy, atmosphere tint and fog tint from solar elevation. Sky3D lights the clouds
from the moving sun; night cloud colors and star visibility fade with twilight.
Moon light also follows phase and elevation, so a new moon does not illuminate
the ground like a full moon.

AgX, SSAO, subtle SSIL and native horizon fog remain enabled. The night profile
keeps roads and silhouettes readable with cold ambient light (energy 0.55, sky
contribution 0.2) and exposure 2.2, easing to exposure 1.05 in daylight. Directional
shadow bias 0.1 / normal bias 1.5 reduces grazing-angle acne on the graybox ground.
The vendor's binary day/night ambient tween is disconnected so it cannot override
the continuous profile.

The editor retains a stopped, editable TimeOfDay reference; runtime receives the
server clock. Sky3D's independent game/editor/system clocks stay disabled. Native
clients instantiate the visual scene; server/headless worlds keep only the clock.
The V1 review fixture temporarily freezes its reference at 15:30 and then restores
the live clock, preserving the earlier comparison workflow.

## Verification

From the repository root:

```powershell
git diff --check
& ./tests/run-smoke.ps1 -NodeExecutable '<Node executable>'
& ./tests/run-combat.ps1 -Scene world_time_network -MarkerPrefix WORLD_TIME
& ./tests/run-visual-v0.ps1 -Scene visual_v2 -RenderingMethod forward_plus
python ./tools/encode-visual-timelapse.py .godot/verification/visual-v2-timelapse .godot/verification/visual-v2-day-night.gif
```

The final encoding command optionally needs Pillow; it is not a runtime dependency.
Both network/native fixtures use port 18098 and must run sequentially.

The new network fixture protects contracts absent from existing gameplay suites:
shared calendar across maps and two clients, later entry, epoch reconstruction,
extrapolation/periodic resync, forward midnight rollover and invalid/stale/delayed
sample handling. All three processes pass. Default smoke and 74 Web UI contracts
pass. The authored scene also opens under the headless editor without script,
parse or scene-load errors; inherited editor/shutdown diagnostics remain.

The native fixture reuses the complete V0 CEF lifecycle, synthetic input/drag,
Shop purchase, Upgrade and confirmed combat pass. It checks the actual client
receives server time, the server omits visual nodes, and the sun/exposure remain
continuous over 721 samples spanning a full day. It captures nine hour views,
a separate full-moon/star view, and 91 native timelapse frames. Native V2 passes
with accelerated CEF OSR supported. These are review artifacts, not pixel tests.
Visual review covers warm dawn/sunset, readable blue night and the textured moon.
Two final repeats timed out at the earlier synthetic Inventory drag. The shared
fixture now waits for native interactive-region routing and acknowledges the CEF
item press before sending drag motion; the next complete native pass succeeds.

Windows client / ServerWindows / ServerUbuntu resource-pack checks and applicable
headless pack boots pass. This establishes resource boundaries, not a distributable
native executable. Physical input, DPI/alt-tab/IME and authenticated route playtest
remain separate from the automated native fixture.

Ignored outputs are under `.godot/verification/visual-v2-*`. The GIF is 960×540;
source captures are 1280×720. Optional local development character assets appear
in the renders but remain outside Git and production exports. The short final
game-viewport sample on RTX 4070 measured GPU median 1.502 ms / p95 2.948 ms and
frame median 7.143 ms / p95 9.091 ms over 381 frames with VSync. It excludes CEF
GPU work and does not measure performance over the complete day/night cycle.
