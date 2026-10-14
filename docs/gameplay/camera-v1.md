# Camera v1

The client now has a small independent MMO/ARPG camera rig. `GameWorld3D` supplies
the already interpolated local character position after its usual presentation
update. The rig never writes character position/rotation or sends RPCs. Manual WASD is
projected onto the rendered camera right/forward axes on the ground plane before
the existing movement/assist flow sends its bounded XZ intention. NPC approach
and combat assist retain their world-space directions. Pitch does not change
movement speed; World still validates intentions and simulates physics. The server
creates no camera. Turning the view alone does not turn the character.

## Controls and configuration

Hold RMB over the world to orbit; upward mouse motion lowers orbit elevation and downward motion raises it. Release to restore the cursor to its previous
position. Wheel zoom is smooth. Escape, focus loss, opening a modal/settings,
leaving the map and shutdown release orbit capture. Mouse gestures started over
CEF stay with CEF. A world orbit keeps ownership if the cursor crosses a Web
window; ending it restores normal Web hit regions. UI carrying items continues
to own its full-screen pointer region, including RMB cancellation.

`source/client/camera/camera_v1.tres` uses the exported settings from
`camera_settings.gd`. Override fields in the resource without editing gameplay:

| Setting | Default |
| --- | --- |
| Distance min / default / max | 4 / 8 / 12 m |
| Pitch min / default / max | -15 / 40 / 65 degrees |
| Orbit sensitivity | 0.25 degrees per mouse pixel |
| Zoom speed | 1 m per wheel step |
| Position / orbit / zoom damping | 12 / 24 / 12 per second |
| Collision return damping | 8 per second |
| Collision sphere radius / margin / skin | 0.25 / 0.05 / 0.02 m |
| Collision mask | Layer 1 (terrain / buildings / rocks) |
| Pivot height / signed forward offset | 1.3 / -0.35 m |
| FOV / near clip | 55 degrees / 0.05 m |
| Auto-align | Disabled; optional 3 s delay, strength 0.5 |

Positive pitch places the camera above the pivot. Negative pitch can lower the
view, but terrain collision retracts the boom before it enters the ground.
The pivot sits slightly behind the player along the camera's horizontal view,
independently of character yaw. The signed forward offset can be tuned in the resource.
Auto-align, when enabled in the resource, only softly follows sustained movement
after the manual-input delay. There is no camera settings UI in this slice.

## Collision and damping

The rig uses exponential damping for follow/orbit/zoom and a sphere sweep for the
pivot-to-camera boom. Framing offset and follow lag are also swept from the player's
eye so the pivot does not drift through nearby scenery. The framing offset drops temporarily near corners if it would obstruct the direct
player-to-camera sightline. Requested zoom stays
separate from resolved distance. Obstructions retract the camera immediately;
only returning to a clear distance is damped. Smoothing never interpolates an
unchecked camera position through a wall. First snapshot/large teleports reset
follow lag rather than flying across the map.

The clearance margin is included in the sphere radius, so overlap tests and
motion sweeps use the same volume. Resolved sweeps retain a small skin so the next sweep does not start on the
contact boundary and falsely collapse an outward camera boom.
The starting sphere is checked for overlap because Godot's `cast_motion` ignores
initially overlapping shapes. See the official
[PhysicsDirectSpaceState3D API](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html).
Player/mob/NPC layers are excluded from scenery queries. Environment visuals must
have matching layer-1 collision geometry; scenery without colliders cannot block
a physics query. Narrow spaces may force the camera closer than the normal minimum
zoom. This v1 does not fade scenery or characters, and malformed spawn points
inside solid geometry need fixing in level content.

## Verification

`./tests/run-camera.ps1` is an optional bounded headless fixture: pitch/zoom bounds,
a real wall and terrain, near-wall rear framing, outward sweeps from a clamped
pivot, collision retraction and return, requested zoom retention,
NPC screen-ray picking after orbit/zoom, independent follow and teleport reset.
It does not assert pixels, exact animation times or combat balance. Existing
Web bridge tests cover temporary world pointer ownership and restoration.
`run-spike3d` verifies the unchanged authoritative movement flow with two clients.

Manual acceptance remains necessary for visual feel/native CEF:

- Orbit and min/max zoom during group combat; framing/readability and damping.
- Walls/pillar/terrain while orbiting; no camera clipping and smooth return.
- Wheel/RMB over Inventory and Upgrade; no accidental camera gestures.
- World orbit across Web windows, RMB release, Escape and Alt-Tab.
- Item carry/right-click, window dragging and native Options while orbiting.
- NPC click/approach and Inventory-to-Blacksmith drop after changing the camera.

No camera API is added to the Web command dispatcher; future framing/shake modes
are deferred. This is a presentation slice, not a character-controller refactor.
