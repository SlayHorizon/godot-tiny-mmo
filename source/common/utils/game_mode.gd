class_name GameMode
## Runtime role detection. Wraps the cmdline `--mode=X` arg with a fallback to
## OS.has_feature so the same code works in both:
##   1. Unified-binary deploys (one Linux server binary launched as
##      `--mode=master-server` / `--mode=gateway-server` / `--mode=world-server`).
##   2. Per-role exports where the role is baked in via the preset's
##      `custom_features`.
##
## Use these checks anywhere code needs to branch on role at runtime. Only the
## client/server *boundary* should still use OS.has_feature("client") directly,
## because client autoloads are gated at process start before this class loads.

const MODE_CLIENT: String = "client"
const MODE_MASTER: String = "master-server"
const MODE_GATEWAY: String = "gateway-server"
const MODE_WORLD: String = "world-server"

## Computed once at first access. The cmdline wins so a feature-baked binary
## can still be re-routed for debugging via `--mode=`.
static var _mode: String = _detect()


static func mode() -> String:
	return _mode


static func is_master_server() -> bool:
	return _mode == MODE_MASTER


static func is_gateway_server() -> bool:
	return _mode == MODE_GATEWAY


static func is_world_server() -> bool:
	return _mode == MODE_WORLD


static func is_client() -> bool:
	return _mode == MODE_CLIENT


## True for any of the three server roles (master/gateway/world).
static func is_any_server() -> bool:
	return _mode == MODE_MASTER or _mode == MODE_GATEWAY or _mode == MODE_WORLD


static func _detect() -> String:
	var arg: String = CmdlineUtils.get_parsed_args().get("mode", "")
	if not arg.is_empty():
		return arg
	# Fallback to feature flags for builds that bake the role in.
	for candidate: String in [MODE_CLIENT, MODE_MASTER, MODE_GATEWAY, MODE_WORLD]:
		if OS.has_feature(candidate):
			return candidate
	return ""
