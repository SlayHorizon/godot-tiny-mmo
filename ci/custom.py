# custom.py — SCons option defaults for slim Ekonia export-template builds.
#
# Godot's SConstruct auto-loads a file named custom.py from the engine source
# root; build-templates.yml copies this there before compiling. The game is
# 100% 2D with ENet/WebSocket networking, so a stack of unused modules is
# dropped with zero gameplay impact.
#
# KEPT (do NOT disable): enet + websocket (web multiplayer rides WebSocket),
# freetype + the advanced text server (fonts + the emoji fallback), and the
# multiplayer module (it's an MMO).

# Smaller, optimized, stripped release templates.
optimize = "size"
lto = "full"
production = "yes"

# Unused modules — verified absent from the codebase (no 3D, XR, video, camera,
# CSG, gridmap, navmesh, or 3D raycast/lightmapper usage anywhere).
module_openxr_enabled = "no"
module_mobile_vr_enabled = "no"
module_webm_enabled = "no"
module_camera_enabled = "no"
module_csg_enabled = "no"
module_gridmap_enabled = "no"
module_raycast_enabled = "no"
module_lightmapper_rd_enabled = "no"
module_navigation_enabled = "no"

# NOTE: the BIGGEST win — stripping all 3D *classes* (Node3D etc.) — comes from
# a Godot "engine build profile" (.build), added in a follow-up once this
# pipeline is green. Module flags above are the safe first pass.
