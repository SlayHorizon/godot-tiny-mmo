# Root CEF addon integration

Accepted and verified locally on 2026-10-09. The copied gameplay project under
`.godot/cef-client/project` is retired. All roles use the actual source checkout.

## Setup

Windows x64, Godot 4.7.2, Python 3.11+:

```powershell
python ./tools/cef_client/setup.py
# Install, import and run the client:
& ./tools/cef_client/run.ps1
# Install and import only, without a game window:
& ./tools/cef_client/run.ps1 -SetupOnly
```

The installer downloads/checks the pinned godot-cef **v2.0.0** archive, extracts
its Windows payload into `addons/godot_cef` and stages available optional skin
PNGs. Version, SHA-256 and installation code are committed; upstream release
payloads stay ignored. The archive remains in `.godot/cef-client/cache`.
No game sources, asset trees or project configuration are copied. After setup,
run the root project from the editor or CLI. Source changes are immediately
visible without refreshing another project.

Root defaults: Vulkan Forward+, 1920×1080 design resolution, 1280×720 initial
window, disabled canvas stretch. UI scale remains independent of window size.
CEF settings and permission/profile defaults are in the root `project.godot`.
CEF is GDExtension, so an Editor Plugins checkbox is not its runtime switch.

The [Visual V0 pass](visual-upgrade-v0.md) verified native Forward+ and Mobile
with the installed pinned addon on 2026-10-12. `run.ps1` defaults to Forward+;
`-RenderingMethod mobile` runs the comparison without editing project settings.
`WebUiHost` checks Vulkan, the installed addon and a non-headless display, rather
than requiring Mobile. Physical input and distributable packaging remain separate gates.

## Server and export boundary

`ServerUbuntu` and `ServerWindows` are dedicated-server presets; both exclude
`addons/godot_cef/*` and the bundled HTML/CSS/JS. They retain SQLite. The same
server package can run gateway/master/world using the normal `--mode` argument.
Separate exports per role are unnecessary for the current shared runtime.

The `Windows` client preset retains CEF and bundles the HTML/CSS/JS. The existing
Tiny MMO export plugin also includes optional skin PNG originals; CEF reads
bytes, not Godot's imported `.ctex` textures. The upstream `.gdextension` manifest
declares native libraries/helpers/data for regular executable export. Pack-only
exports are not complete distributable clients and do not prove native DLL staging.

`LegacyWebUnsupported` and `LegacyAndroidUnsupported` exclude CEF and are retained
reference targets, not supported releases. `LinuxClientUnverified` retains Web UI,
but Linux client installation is not supplied
by this Windows installer; Linux/macOS client release setup is still unverified.

Export filters apply only during export. In local `--headless --path .` runs,
Godot loads installed GDExtensions. CEF registers classes and installs Vulkan
hooks; this is visible in logs. `WebUiHost` refuses browser creation in headless.
No CEF helper processes were observed in the headless checks. If development
runs must be entirely free of native CEF, run an exported server package.
Do not toggle `.gdignore` or extension lists between concurrently running roles.

## Verification

Default prototype smoke remains unchanged in scope and needs no CEF installation.
For addon/export changes only:

```powershell
& ./tests/run-cef-export.ps1
```

This optional, headless runner exports client/server ZIP resource packs, checks
CEF registration/exclusion and client Web resources/raw skin images, then boots
the Windows client and server packs with the bridge/UID contract. Client command
validation runs without SQLite; the server package must omit CEF. Successful runs remove their
ZIPs and retain fixed-name logs in `.godot/verification`.

Local results:

- Root headless import with installed addon: passed.
- Five persistence smoke scenarios and JS/Godot bridge contracts: passed.
- Real headless World Server/two-client Inventory RPC regression: passed.
- Windows client pack: CEF registered; HTML/CSS/JS and raw skin PNGs present.
- Client-pack headless boot: real Inventory UID validation passed without SQLite.
  Stub constructors/void overrides and Error returns preserve valid signatures.
- Windows/Linux server packs: no CEF resources or extension-list entry.
- Windows server-pack headless boot: bridge contract passed, no CEF initialization.
- No surviving CEF helper processes observed; no game windows opened.

Existing upstream resource/ObjectDB shutdown warnings remain. Pack export also
reports an inherited `translations.csv` import warning while completing; this
change does not claim a clean full release build. No full client executable,
native graphics/input or Linux server execution was tested in this cleanup.
Native packaging and non-debug client launch remain release gates, alongside
those in [the Web UI documentation](web-ui.md). Remote CI has not been run locally.

The cleanup helper removes the retired copied project, not the root addon,
archive cache, reference checkout or game data.
