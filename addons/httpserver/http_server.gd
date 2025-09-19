extends Node
#class_name HTTPServer


const HttpRouter = preload("res://addons/httpserver/http_router.gd")

var server: TCPServer
var router: HttpRouter

var current_connections: Array[StreamPeerTCP]
var time: float
var to_wait: float = 2.0


func _ready() -> void:
	server = TCPServer.new()
	router = HttpRouter.new()
	server.listen(8088, "127.0.0.1")


func _physics_process(delta: float) -> void:
	if server.is_connection_available():
		var connection: StreamPeerTCP = server.take_connection()
		handle_connection(connection)
		current_connections.append(connection)
	time += delta
	if time >= to_wait:
		for connection: StreamPeerTCP in current_connections:
			handle_connection(connection)
		time = 0.0


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
	
	var as_string: String = connection.get_string(available_bytes)
	if not as_string.contains("\r\n\r\n"):
		return
	
	var headers: String = as_string.get_slice("\r\n\r\n", 0)
	if headers.is_empty() or headers == as_string:
		return
	
	var header: PackedStringArray = headers.get_slice("\r\n", 0).split(" ")
	var method: String = header[0]
	var path: String = header[1]
	
	var payload: Dictionary = JSON.parse_string(
		as_string.get_slice("\r\n\r\n", 1)
	)
	
	var handler: Callable = router.find_route_handler(
		HTTPClient.Method.METHOD_POST,
		path
	)
	
	var result: Dictionary
	if handler.is_valid():
		result = await handler.call(payload)
	else:
		result = {"error":"not_found555"}
	
	http_send(
		connection,
		result,
		HTTPClient.ResponseCode.RESPONSE_OK
	)
	connection.disconnect_from_host()
	current_connections.erase(connection)
	


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
		"Connection": "close"
	}
	var header_to_buffer: String = "HTTP/1.1 %d OK\r\n" % code
	
	for header: String in headers:
		header_to_buffer += "%s: %s\r\n" % [header, str(headers[header])]
	header_to_buffer += "\r\n"
	
	# Header block
	connection.put_data(header_to_buffer.to_ascii_buffer())
	# Content/Body block
	connection.put_data(body_buffer)
	
	current_connections.erase(connection)
	connection.disconnect_from_host()
