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

# No 3D anywhere in the game — drop all 3D classes and servers. This is the
# single biggest size win, and since Godot 4.5 it's a plain SCons flag (no
# engine build profile needed).
disable_3d = "yes"

# Unused modules — verified absent from the codebase (no XR, video, camera,
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

# NOTE: Vulkan + D3D12 removal lives in build-templates.yml as platform-specific
# flags (the web build never registers those variables, so they can't go here).
# The project renders with gl_compatibility, so both backends are dead weight on
# desktop — safe to strip.
