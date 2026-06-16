class_name GatewayAPI

## Shared keys (client + gateway)
const KEY_REQUEST_ID: String = "r-id"
const KEY_TOKEN_ID: String = "t-id"
const KEY_ACCOUNT_ID: String = "a-id"
const KEY_ACCOUNT_USERNAME: String = "a-u"
const KEY_ACCOUNT_PASSWORD: String  = "a-p"
const KEY_WORLD_ID: String = "w-id"
const KEY_CHAR_ID: String = "c-id"
## Client build version (the project's config/version), sent on login so an
## outdated client gets a clear "please update" message instead of failing deeper.
const KEY_CLIENT_VERSION: String = "c-v"


## Auth/gateway error codes (server → client). Kept here so client and server
## agree on the numbers; the client maps them to localized text in GatewayError.
## Anything not listed falls back to a generic "please try again" on the client.
const ERR_GENERIC: int = 1
const ERR_ACCOUNT_CREATE_FAILED: int = 30
const ERR_BAD_CREDENTIALS: int = 50
const ERR_ALREADY_CONNECTED: int = 51
const ERR_RATE_LIMITED: int = 60
## Client build doesn't match the server's. The boot handshake (and login) return
## this so the client can show a hard "please update" instead of letting them in.
const ERR_OUTDATED_VERSION: int = 70


## This build's version, from project.godot's application/config/version. Same
## call returns the client's version on the client and the server's on the server.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

const ACTION_LOGIN := "login"
const ACTION_CREATE_ACCOUNT := "create_account"
const ACTION_CREATE_CHARACTER := "create_character"
const ACTION_LIST_CHARACTERS := "list_characters"
const ACTION_ENTER_WORLD := "enter_world"
const ACTION_DISCONNECT := "disconnect"


static func base_url() -> String:
	if OS.has_feature("ekonia") or OS.has_feature("release"):
		return "https://ws.ekoniaonline.com"
	return "http://127.0.0.1:8088"

	# var command_line_arg: String = CmdlineUtils.get_parsed_args().get("api", "")
	# if command_line_arg:
	# 	return command_line_arg
	#
	# # Check if has default in ProjectSettings
	# # (set different values for debug/release export presets)).
	# var value: String = ProjectSettings.get_setting("network/api/base_url", "")
	# if not value.is_empty():
	# 	return value
	# return "http://127.0.0.1:8088"


static func get_endpoint(path: String) -> String:
	return "%s%s" % [base_url().rstrip("/"), path]


# Endpoints
static func login() -> String:
	return get_endpoint("/v1/login")


static func guest() -> String:
	return get_endpoint("/v1/guest")


static func worlds() -> String:
	return get_endpoint("/v1/worlds")


## Lightweight boot healthcheck (no auth): is the gateway reachable + master up, and
## does this build match the server's? Called before the gateway shows any menu.
static func handshake() -> String:
	return get_endpoint("/v1/handshake")


static func account_create() -> String:
	return get_endpoint("/v1/account/create")


static func world_characters() -> String:
	return get_endpoint("/v1/world/characters")


static func world_enter() -> String:
	return get_endpoint("/v1/world/enter")


static func world_create_char() -> String:
	return get_endpoint("/v1/world/character/create")
