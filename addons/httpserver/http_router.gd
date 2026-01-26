extends RefCounted
#class_name HttpRouter
## My implementation doesn't use class_name to not flow global project classes.
## Feel free to change this while waiting namespacing or else.

## Route name /v1/login then a map with its methods and handlers:
## [&"/v1/login/": {Method.GET: _get_login}]
var routes: Dictionary[StringName, Dictionary]

## [{ "prefix": StringName, "method": int, "handler": Callable }]
var prefix_routes: Array[Dictionary]
## [{ "prefix": String, "dir": String, "index": String }]
var static_mounts: Array[Dictionary]


func register_route(
	method: HTTPClient.Method,
	path: StringName,
	handler: Callable
) -> void:
	if routes.has(path):
		routes[path][method] = handler
	else:
		routes[path] = {method: handler}


func register_prefix_route(method: HTTPClient.Method, prefix: StringName, handler: Callable) -> void:
	prefix_routes.append({"prefix": prefix, "method": method, "handler": handler})


func register_static_dir(prefix: StringName, dir: String, index_file: String = "index.html") -> void:
	static_mounts.append({"prefix": String(prefix), "dir": dir, "index": index_file})


func find_route_handler(method: HTTPClient.Method, path: StringName) -> Callable:
	if routes.has(path):
		return routes[path].get(method, Callable())

	var best_prefix: String
	var best_handler: Callable
	var path_str: String = String(path)

	for r: Dictionary in prefix_routes:
		if r.get("method", -1) != int(method):
			continue

		var pfx: String = r.get("prefix", "")
		if path_str.begins_with(pfx) and pfx.length() > best_prefix.length():
			best_prefix = pfx
			best_handler = r.get("handler", Callable())

	return best_handler


func dispatch(method: HTTPClient.Method, path: StringName, payload: Variant) -> bool:
	var handler: Callable = find_route_handler(method, path)
	if handler.is_valid():
		handler.call(payload)
		return true
	return false
