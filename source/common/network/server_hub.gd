class_name ServerHub

## SlayHorizon: DEPRECATED NOW WE USE PLUGIN EXPORT SO STRIP SERVER CONTENT
## THIS SCRIPT SHOULD BE REMOVED IMO AND PROJECT REFACTORED TO NOT USE IT ANYMORE

## Indirection handle for the live server runtime. Common-side code that needs
## to call into server behaviour (data_push, propagate_rpc, instance lookups,
## etc.) goes through ServerHub.current instead of importing concrete classes
## like WorldServer or ServerInstance directly.
##
## Why: the GDScript parser must resolve every type identifier it sees, even
## inside dead branches that never run. If common files referenced server-only
## classes, the client/web exports would have to ship source/server/ to keep
## the parser happy. This indirection breaks that dependency — common only
## sees `Node`, the server fills the slot at boot, and the client never
## touches it.
##
## Set once by the live server (WorldServer._ready does it). On client builds
## it stays null and the server-only code paths that touch it never fire.

static var current: Node
