# Pixel-exact local UI cache

`tools/dev_assets/export_ui.py` exports only explicitly selected `.sub`, `.dds`
and `.tga` files. It does not scan packs, create atlases, resize, retouch, sharpen,
flip, apply color correction or premultiply alpha. Gameplay and Web UI do not
load this cache automatically yet.

Python 3.12+ and Pillow are developer-tool dependencies, not game dependencies:

```powershell
python -m pip install -r tools/dev_assets/requirements-ui.txt
$env:MANDATE_LEGACY_UI_SOURCE_ROOT = 'X:/Local Reference/ymir work/ui'
python tools/dev_assets/export_ui.py public/slot_base.sub public/close_button_01.sub pattern/board_corner_lefttop.tga
```

Alternatively pass `--source-root 'X:/Local Reference/ymir work/ui'`. The source
root must exist outside the Godot project. It is the client's UI search root,
not the entire pack directory. No absolute source path is stored in game code.

The local cache is `dev_assets/legacy/ui_cache/`. Original directory structure
and names are retained, appending `.png` to the complete filename, e.g.
`public/slot_base.sub.png`. This avoids collisions between `button.sub` and
`button.tga`. `manifest.json` records original source and texture paths/spelling,
the original `.sub` fields/image reference, rectangle, dimensions, source hashes,
Pillow version, fingerprint and PNG/decoded RGBA hashes. Cache and manifest are
ignored by Git and covered by existing dev_assets export exclusions.

## Exact interpretation

- `.sub` 1.0 resolves `image` relative to the configured UI search root.
- `.sub` 2.0 resolves `image` relative to the `.sub` file's directory.
- Lookups accept Windows separators and case-insensitive names, while the
  manifest retains both the declared reference and actual filesystem spelling.
- Rectangles use `[left, top, right, bottom]`, with right/bottom exclusive.
  Output dimensions are exactly `right-left` by `bottom-top`.
- Invalid/empty/negative rectangles and out-of-bounds regions fail. No padding
  or clamping hides incorrect metadata.
- Standalone images use the entire image at its original dimensions.

Pillow handles DDS/TGA decoding and PNG encoding; no image decoder is implemented.
See its [format documentation](https://pillow.readthedocs.io/en/stable/handbook/image-file-formats.html).
Lossless means equality to the **decoded 8-bit RGBA pixels**, including alpha and
RGB values of transparent pixels. It does not mean recovery of pixels lost when
a DDS was originally compressed, or copying DDS mipmaps into PNG.

Every newly exported PNG is reread and compared byte-for-byte with the selected
RGBA pixels before atomically replacing its target. Invalid inputs preserve the
previous PNG and manifest entry. Cache hits require unchanged source/texture
hashes, decoder/algorithm fingerprint and output hash; changed/tampered files
are rebuilt. Unselected entries are left alone. Failures are reported per file;
other selections continue, and any failure returns exit code 1. Traversal,
external source escapes and destination symlinks/junctions are rejected.

## Verification

```powershell
python -m unittest discover -s tests -p test_ui_cache.py -v
```

Tests generate synthetic images only. They cover `.sub` versions/search rules,
exclusive bounds, exact crop/standalone RGBA, cache invalidation, previous-output
preservation, explicit selection, malformed metadata and path/link boundaries.
CI does not use third-party files. Deleting the cache has no runtime effect.
