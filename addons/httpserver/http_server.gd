extends Node
#class_name HTTPServer


const HttpRouter = preload("res://addons/httpserver/http_router.gd")

const DEFAULT_BIND_ADDRESS: String = "127.0.0.1"
const MAX_REQUEST_BYTES: int = 1024 * 1024 # 1 MiB safety cap

var server: TCPServer
var router: HttpRouter

var current_connections: Array[StreamPeerTCP]


func _ready() -> void:
	server = TCPServer.new()
	router = HttpRouter.new()


func _physics_process(delta: float) -> void:
	if server.is_connection_available():
		var connection: StreamPeerTCP = server.take_connection()
		current_connections.append(connection)
	for connection: StreamPeerTCP in current_connections:
		handle_connection(connection)


func listen(port: int, bind_address: String = "*") -> void:
	server.listen(port, bind_address)


func close_connection(connection: StreamPeerTCP) -> void:
	connection.disconnect_from_host()
	current_connections.erase(connection)


func handle_connection(connection: StreamPeerTCP) -> void:
	# Update status
	connection.poll()
	# Get and Check status
	var status: StreamPeerTCP.Status = connection.get_status()
	if status == StreamPeerTCP.Status.STATUS_NONE or status == StreamPeerTCP.Status.STATUS_ERROR:
		current_connections.erase(connection)
		return
	if status == StreamPeerTCP.Status.STATUS_CONNECTING:
		return

	var available_bytes: int = connection.get_available_bytes()
	if not available_bytes:
		return

	if available_bytes > MAX_REQUEST_BYTES:
		close_connection(connection)
		return

	var as_string: String = connection.get_string(available_bytes)
	if not as_string.contains("\r\n\r\n"):
		# Not full headers yet.
		return

	var headers: String = as_string.get_slice("\r\n\r\n", 0)
	if headers.is_empty() or headers == as_string:
		return

	var header: PackedStringArray = headers.get_slice("\r\n", 0).split(" ")

	var method_str: String = header[0]
	var method: HTTPClient.Method = HTTPClient.Method.METHOD_GET

	match method_str:
		"GET":
			method = HTTPClient.Method.METHOD_GET
		"HEAD":
			method = HTTPClient.Method.METHOD_HEAD
		"POST":
			method = HTTPClient.Method.METHOD_POST
		"PUT":
			method = HTTPClient.Method.METHOD_PUT
		"DELETE":
			method = HTTPClient.Method.METHOD_DELETE
		"OPTIONS":
			method = HTTPClient.Method.METHOD_OPTIONS
	
	# Hardcoded CORS handler
	if method == HTTPClient.Method.METHOD_OPTIONS:
		http_send(connection, {}, HTTPClient.ResponseCode.RESPONSE_OK)
		close_connection(connection)
		return

	# If browser sends "/v1/foo?bar=baz", keep only path for routing.
	var path: String = header[1].get_slice("?", 0)
	if _try_serve_static(connection, method, path):
		close_connection(connection)
		return

	var payload: Dictionary
	var body: String = as_string.get_slice("\r\n\r\n", 1)
	if body.strip_edges() != "":
		var parsed: Variant = JSON.parse_string(body)
		if typeof(parsed) == TYPE_DICTIONARY:
			payload = parsed

	payload["__path__"] = path
	var handler: Callable = router.find_route_handler(method, path)
	var result: Dictionary
	if handler.is_valid():
		result = await handler.call(payload)
	else:
		result = {"ok": false, "error":"not_found"}


	if result.get("__raw__", false):
		var code: int = result.get("code", 200)
		var ct: String = result.get("content_type", "text/plain; charset=utf-8")
		var _body: PackedByteArray = result.get("body", PackedByteArray())
		http_send_bytes(connection, _body, code, ct)
	else:
		http_send(connection, result, HTTPClient.ResponseCode.RESPONSE_OK)

	close_connection(connection)


func http_send(
	connection: StreamPeerTCP,
	payload: Dictionary,
	code: HTTPClient.ResponseCode
) -> void:
	## to_utf8_buffer for more support
	var body_buffer: PackedByteArray = JSON.stringify(payload).to_ascii_buffer()
	var headers: Dictionary = {
		"Content-Type": "application/json",
		"Content-Length": body_buffer.size(),
		"Connection": "close",

		# CORS
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "POST, GET, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type"
	}
	var header_to_buffer: String = "HTTP/1.1 %d OK\r\n" % code
	
	for header: String in headers:
		header_to_buffer += "%s: %s\r\n" % [header, str(headers[header])]
	header_to_buffer += "\r\n"
	
	# Header block
	connection.put_data(header_to_buffer.to_ascii_buffer())
	# Content/Body block
	connection.put_data(body_buffer)


func http_send_bytes(
	connection: StreamPeerTCP,
	body: PackedByteArray,
	code: int,
	content_type: String
) -> void:
	var headers: Dictionary = {
		"Content-Type": content_type,
		"Content-Length": body.size(),
		"Connection": "close",

		# CORS (optional)
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "POST, GET, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type"
	}

	var header_to_buffer := "HTTP/1.1 %d OK\r\n" % code
	for header in headers.keys():
		header_to_buffer += "%s: %s\r\n" % [header, str(headers[header])]
	header_to_buffer += "\r\n"

	connection.put_data(header_to_buffer.to_ascii_buffer())
	connection.put_data(body)


func _mime_for(file_path: String) -> String:
	var ext: String = file_path.get_extension().to_lower()
	match ext:
		"html": return "text/html; charset=utf-8"
		"css": return "text/css; charset=utf-8"
		"js": return "application/javascript; charset=utf-8"
		"json": return "application/json; charset=utf-8"
		"png": return "image/png"
		"jpg", "jpeg": return "image/jpeg"
		"svg": return "image/svg+xml"
		"ico": return "image/x-icon"
		"woff": return "font/woff"
		"woff2": return "font/woff2"
		"ttf": return "font/ttf"
		_: return "application/octet-stream"


func _is_bad_path(req_path: String) -> bool:
	return req_path.contains("..") or req_path.contains("\\") or req_path.contains(":")


func _try_serve_static(connection: StreamPeerTCP, method: HTTPClient.Method, path: String) -> bool:
	if method != HTTPClient.Method.METHOD_GET:
		return false

	if path.begins_with("/v1/"):
		return false

	var best_prefix: String
	var best_mount: Dictionary

	for mount in router.static_mounts:
		var prefix: String = mount.get("prefix", "")
		if path.begins_with(prefix) and prefix.length() > best_prefix.length():
			best_prefix = prefix
			best_mount = mount

	if best_mount.is_empty():
		return false

	var rel_path: String
	if best_prefix == "/":
		rel_path = path
	else:
		# Remove the mount prefix; keep the remainder as a path
		rel_path = path.trim_prefix(best_prefix)

	if rel_path.is_empty() or rel_path == "/":
		rel_path = "/" + String(best_mount.get("index", "index.html"))

	if not rel_path.begins_with("/"):
		rel_path = "/" + rel_path

	if _is_bad_path(rel_path):
		http_send_bytes(connection, "Bad path".to_utf8_buffer(), 400, "text/plain; charset=utf-8")
		return true

	var base_dir: String = String(best_mount.get("dir", "")).trim_suffix("/")
	var file_path: String = base_dir.path_join(rel_path.trim_prefix("/"))

	if not FileAccess.file_exists(file_path):
		http_send_bytes(connection, "Not found".to_utf8_buffer(), 404, "text/plain; charset=utf-8")
		return true

	http_send_bytes(connection, FileAccess.get_file_as_bytes(file_path), 200, _mime_for(file_path))
	return true
