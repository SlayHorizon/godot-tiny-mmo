# Visual Upgrade V0 — renderer and CEF

Accepted and locally verified on 2026-10-12: desktop uses **Forward+ / Vulkan**.
The former Mobile-only check was our composition policy, not a demonstrated CEF
requirement. Godot CEF's [Vulkan integration](https://godotcef.org/api/vulkan-support.html)
shares accelerated textures through Vulkan hooks. We verified the installed
pinned godot-cef v2.0.0 on Godot 4.7.2, Windows x64 and RTX 4070.

`project.godot` now selects `forward_plus`, declares the matching editor feature
and explicitly selects Vulkan on Windows. The CEF launcher uses the same default;
its `-RenderingMethod mobile` option enables a comparison. `WebUiHost` requires
a non-headless display, CefTexture registration and Vulkan, without a Mobile
rendering-method check. Headless still never composes a browser.

No extra rendering thread or VSync workaround was needed. Early fixture attempts
failed to correlate JSON numeric IDs and used an incorrectly escaped DOM selector;
the final pass corrected those test defects and ran with the normal render thread
and VSync. These attempts are not evidence of an engine/addon deadlock.

## Repeatable native pass

Install/import the pinned addon and build Web UI as described in
[CEF integration](cef-addon-integration.md), then run from the repository root:

```powershell
& .\tests\run-visual-v0.ps1
# Forward+ only:
& .\tests\run-visual-v0.ps1 -RenderingMethod forward_plus
# Normal authenticated client (requires the normal servers):
& .\tools\cef_client\run.ps1
# Mobile comparison client:
& .\tools\cef_client\run.ps1 -RenderingMethod mobile
```

The native runner starts one disposable headless world and one native client,
sequentially for each renderer. It reuses `pve_network.gd` with the actual First
Region, temporary SQLite characters and isolated APPDATA/LOCALAPPDATA. It needs
no running gateway/master/world or real accounts. Port 18098 is shared with the
PvE-derived suites; do not run them concurrently. Tests use the production CEF
page, controller, native input routing and server RPC handlers, with diagnostic
JavaScript and phase RPCs confined to the fixture.

## Verified behavior

Both Mobile and Forward+ passed the same native fixture, with exit code zero:

- Eager CEF creation and real production Inventory/Equipment DOM; I open/close/reopen.
- Synthetic mouse drag travels through Godot input, CEF DOM, bridge and the real
  move RPC, producing an authoritative item revision.
- RMB orbit changes the rendered camera while CEF remains open; release returns
  gameplay keyboard ownership. Modal/hide/reopen ownership also passes.
- Reload and browser destruction/recreation restore UI_READY and snapshots.
- Window resize reaches the CEF viewport; native captures show the world and UI.
- Real NPC interaction, Weapon Shop purchase and +0 → +1 Upgrade complete through
  JavaScript → CEF → bridge → authenticated fixture RPC → CEF command result.
- Server-confirmed melee damages a mob on First Region.
- CEF reports `accelerated_osr_supported=true` and accelerated browser creation;
  both initial/recreated surfaces expose `Texture2DRD`. The runner also verifies
  the actual renderer name and Vulkan driver in the result report.

Default smoke and all 74 Web UI contracts passed. Captures/JSON/fixed-name logs
are ignored under `.godot/verification/visual-v0-*`; they are review artifacts,
not committed pixel baselines. Existing ObjectDB/resource shutdown warnings
remain; the checks reject script/parse errors and unsuccessful pass markers.

## Short local performance sample

Same First Region fixture, stationary after one confirmed hit, 3-second sample,
VSync enabled, RTX 4070. The viewport was 1100×780 after the resize step.

| Observation | Mobile | Forward+ |
| --- | ---: | ---: |
| Frame median | 6.944 ms | 6.944 ms |
| Frame p95 | 6.944 ms | 7.407 ms |
| Godot viewport GPU median | 1.358 ms | 1.481 ms |
| Godot viewport GPU p95 | 2.027 ms | 2.294 ms |
| Godot static allocation counter | 178,931,679 bytes | 188,460,254 bytes |

Frame timing is VSync-limited. Viewport GPU timing excludes CEF's independent
GPU work; the static counter is not total process/CEF memory or VRAM. This short
sample supports feasibility on this machine, not a target-device budget or a
soak/performance claim. The reports retain GPU/driver/renderer and sample count.

## Remaining acceptance and next slice

Synthetic native input is not physical mouse/keyboard, IME, DPI, alt-tab or
subjective camera feel. A normal login/session playtest, helper crash/long soak,
full non-debug executable packaging and other GPUs remain separate acceptance.
No release executable was exported in V0. Servers retain their CEF exclusion.

Forward+ remains the integrated desktop default. Next is a bounded V1 environment
baseline on First Region: sky, sun, ambient/reflected light and neutral exposure.
Sky3D/Terrain3D/scatter installation, day/night, water and postprocess tuning are
later visual slices; V0 introduces no art plugins or gameplay/persistence changes.
