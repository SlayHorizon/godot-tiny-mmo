# Mandate CI

`verify.yml` imports a clean Windows checkout, checks whitespace and runs the
small [prototype smoke suite](testing.md) on push/PR. It uses Godot 4.7.2,
Node 24; Python 3.12 is installed only for extended checks. No CEF download, game window, Playwright, real account,
legacy source conversion or release publishing is involved.

Workflow dispatch has an **extended** switch, off by default. It additionally
runs asset staging/UI cache fixtures, visual fallback probes and the existing
sequential gameplay/network suites. These are optional targeted tools while the
game is rapidly prototyped, not a gate for every small UI or balance change.
The UI cache checks install their Pillow dependency only in that extended path.

The default protects item transactions, migration/footprints, pickup uniqueness,
soft progression checkpoints, wallet deltas/critical spend and bridge contracts.
It does not freeze DOM structure, exact pixels, browser timing or combat balance.
Logs are uploaded on failure as well as success. Local smoke execution verifies
the scripts, not the hosted Actions run before publication.

Inherited upstream release/build templates and the legacy conversion CI step
remain removed. Tiny MMO export presets/plugin remain for local use. A future
Mandate release/export setup is a separate deliberate change.

The Node setup action follows its [official usage](https://github.com/actions/setup-node)
with package-manager caching disabled; the project has no frontend dependency install.
