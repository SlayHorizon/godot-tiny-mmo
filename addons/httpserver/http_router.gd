extends RefCounted
#class_name HttpRouter

## Horizon:
## My implementation doesn't use class_name to not flow global project classes.
## Feel free to change this while waiting namespacing or else.

## Route name /v1/login then a map with its methods and handlers:
## [&"/v1/login/": {Method.GET: _get_login}]
var routes: Dictionary[StringName, Dictionary]


func register_route(
	method: HTTPClient.Method,
	path: StringName,
	handler: Callable
) -> void:
	if routes.has(path):
		routes[path][method] = handler
	else:
		routes[path] = {method: handler}


func find_route_handler(method: HTTPClient.Method, path: StringName) -> Callable:
	if routes.has(path):
		return routes[path].get(method, Callable())
	return Callable()


func dispatch(method: HTTPClient.Method, path: StringName, payload: Variant) -> bool:
	var handler: Callable = find_route_handler(method, path)
	if handler.is_valid():
		handler.call(payload)
		return true
	return false
