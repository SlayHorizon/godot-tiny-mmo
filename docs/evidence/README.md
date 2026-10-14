# Evidence and validation

Measured evidence must state **branch/commit**, platform, test command, runtime versions and limitations. A CI green check proves only the suites it actually ran.

## On `main`

- [Testing policy and reproduction](../development/testing.md)
- [CI / platform checks](../development/ci.md)
- [Historical native validation](../history/README.md) (dated results, not current acceptance)
- [Terrain3D adoption and verification](../world/visuals/visual-upgrade-v4-terrain3d.md)

## Auction/Marketplace — on `shop` until PR #1 merges

The `shop` branch contains the Auction D0–D2 reports and evidence under `docs/evidence/`, including the Windows D2 load/recovery measurements. They are deliberately **not copied into `main`** just to make documentation appear current; access them through [PR #1](https://github.com/PatrykCieszynski/Mandate-of-Three/pull/1) or switch to `shop` until merge.

Recorded D2 limitations: Linux runtime not verified, actual native-only SQL timing unavailable from the public addon API, and economy writes still cause measurable simulation tick tails. A benchmark passing on the developer's Windows host is not a production SLA.

This directory retains reproducible raw evidence. The documentation cleanup removes obsolete *plans*, not Auction D2 performance data on `shop`. Large diagnostic P0 data needs separate review after integration.
