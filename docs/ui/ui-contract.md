# Mandate of Three — UI Contract v1

Accepted 2026-10-09. This is the layout contract for screen-space CEF UI.

## Resolution and scale

Base design: **1920×1080 at uiScale 1.0**. Dimensions are logical pixels;
1 logical pixel maps to 1 physical pixel at that baseline. Resolution and UI
scale are independent: larger resolutions expose more world, rather than
implicitly enlarging the UI. Supported user scales: **80, 90, 100, 110, 125,
140 and 150%**. Suggested defaults are 90% at 720p, 100% at 1080p, 110% at
1440p, and 150% at 2160p; these are defaults, not resolution-driven scaling rules.

Godot supplies viewport dimensions, one global `ui_scale`, and authoritative
client state. The same DOM uses a single root transform; core UI dimensions
never use vw/vh or viewport-relative percentages. The root CEF client disables
Godot canvas stretching so its browser surface follows the physical window.

## Anchors and safe frame

Inventory: screen right. Minimap: top-right. Chat: bottom-left. Core HUD:
bottom-center. Target/boss: top-center. Keep core HUD within a centered safe
frame of approximately 1920 logical pixels; ultrawide adds visible world.
Inventory and minimap may anchor to physical screen edges. This inventory slice
does not implement those other screens or their safe-frame layout.

## Inventory and windows

- Fixed slot target: **40×40 logical px**, adjustable through `--slot-size`.
- Five columns; initial implementation: nine rows per page, four pages I–IV.
- Item footprints: 1×1, 1×2, 1×3. No rotation.
- Window target: 230–270 logical px wide. Current chrome requires **266 px**.
- Independent draggable windows; fixed/minimum logical sizes; clamp to viewport.
- Reusable semantic window chrome, titles, close buttons, tabs and footer.
- Avoid dashboard-style fluid resizing. A very small viewport may scroll the
  window vertically without changing slot sizes. Tooltips flip and clamp.

## Assets and DPI

Labels use real fonts. Window frames/buttons use separate corners and repeating
edges or 9-slice/border-image. Prefer individual semantic assets over atlas
coordinates. Legacy extracted PNGs are temporary local reference skin only:
copy them exactly, without resizing, retouching or regenerating them. Keep their
paths isolated from layout and logic.

Final painted UI chrome and icons should tolerate at least 150% UI scale;
prefer 2× raster sources where practical, with browser downscale. Use SVG for
geometric ornaments and high-resolution raster for painted ornaments. Legacy
textures do not satisfy the final-art quality target; they are not final assets.

## Required milestone verification matrix

| Viewport | UI scale |
| --- | --- |
| 1280×720 | 80%, 90% |
| 1920×1080 | 100% |
| 2560×1440 | 100%, 110%, 125% |
| 3440×1440 | 100%, 110% |
| 3840×2160 | 125%, 150% |

The matrix is checked manually at UI milestones during prototyping. Exact
geometry/DOM assertions are not part of the default CI suite.

Responsiveness is limited to edge clamping, tooltip flipping, chat width,
unusually small viewport fallback and ultrawide safe-frame handling. Core
inventory geometry remains fixed across the matrix.
