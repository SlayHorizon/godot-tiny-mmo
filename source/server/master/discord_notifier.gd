class_name DiscordNotifier
## Posts embed messages to a Discord webhook. Use for server-status pings
## (online/offline, world connects, errors) — anything an operator wants to
## see in their phone notifications without opening the dashboard.
##
## Setup:
##   1. In Discord: Channel settings → Integrations → Webhooks → New → copy URL.
##   2. Create user://discord_webhook.cfg or res://data/config/discord_webhook.cfg:
##        [webhook]
##        url="https://discord.com/api/webhooks/..."
##
## All methods are static, fire-and-forget, and silently no-op when no URL is
## configured — so it's safe to leave the calls in code without breaking
## servers that don't use Discord.

const USER_CONFIG_PATH: String = "user://discord_webhook.cfg"
const RES_CONFIG_PATH: String = "res://data/config/discord_webhook.cfg"

# Discord embed colors (decimal RGB).
const COLOR_OK: int = 0x57F287    # green — server up / world connected
const COLOR_WARN: int = 0xFEE75C  # yellow — degraded / non-critical
const COLOR_BAD: int = 0xED4245   # red — server down / world disconnected
const COLOR_INFO: int = 0x5865F2  # blurple — neutral info

static var _url: String
static var _loaded: bool
static var _http_node: HTTPRequest


static func notify(title: String, description: String, color: int = COLOR_INFO) -> void:
	if not _loaded:
		_load()
	if _url.is_empty():
		return
	var embed: Dictionary = {
		"title": title,
		"description": description,
		"color": color,
		"timestamp": Time.get_datetime_string_from_system(true),
	}
	_send({"embeds": [embed]})


# --- Common events as named helpers so call sites stay readable ---

static func notify_master_online() -> void:
	# Version (not host:port — irrelevant behind a reverse proxy) lets an operator
	# confirm at a glance that a deploy actually took effect.
	notify("🟢 Master server online", "Running version `%s`." % GatewayAPI.game_version(), COLOR_OK)


static func notify_master_offline() -> void:
	notify("🔴 Master server offline", "Shutting down.", COLOR_BAD)


static func notify_world_connected(world_name: String) -> void:
	notify("🟢 World connected", "**%s** is online." % world_name, COLOR_OK)


static func notify_world_disconnected(world_name: String) -> void:
	notify("🔴 World disconnected", "**%s** left the master." % world_name, COLOR_BAD)


# --- internals ---

static func _send(body: Dictionary) -> void:
	var http: HTTPRequest = _ensure_http()
	if http == null:
		return
	var err: int = http.request(
		_url,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	# Don't error on failure — Discord webhooks are non-critical.
	if err != OK:
		push_warning("DiscordNotifier: request failed with code %d" % err)


static func _ensure_http() -> HTTPRequest:
	if _http_node != null and is_instance_valid(_http_node):
		return _http_node
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var http: HTTPRequest = HTTPRequest.new()
	http.name = "DiscordNotifierHTTPRequest"
	tree.root.add_child(http)
	_http_node = http
	return http


static func _load() -> void:
	_loaded = true
	var config: ConfigFile = ConfigFile.new()
	var path: String = USER_CONFIG_PATH if FileAccess.file_exists(USER_CONFIG_PATH) else RES_CONFIG_PATH
	if config.load(path) != OK:
		return
	_url = str(config.get_value("webhook", "url", ""))
