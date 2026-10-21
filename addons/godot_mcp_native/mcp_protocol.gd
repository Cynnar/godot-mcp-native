@tool
extends RefCounted
## MCP (Model Context Protocol) over Streamable HTTP.
##
## Stateless and JSON-only: every POST to /mcp is answered with a single JSON
## response. There is no SSE stream, so GET returns 405 (allowed by the spec).

const SERVER_NAME := "godot-mcp-native"
const SERVER_VERSION := "0.1.0"
const SUPPORTED_VERSIONS := ["2025-06-18", "2025-03-26", "2024-11-05"]
const ENDPOINT := "/mcp"
const LOCAL_HOSTS := ["127.0.0.1", "localhost"]

var _registry


func _init(registry) -> void:
	_registry = registry


## HTTP entry point. Matches the handler signature expected by http_server.gd.
func handle_http(method: String, target: String, headers: Dictionary, body: String) -> Dictionary:
	var path := target.split("?")[0]

	# Security: this server can edit the user's project, so only accept requests
	# that look like they come from a local, non-browser client. Checking Host
	# blocks DNS-rebinding; checking Origin blocks cross-site browser requests.
	if not _host_allowed(str(headers.get("host", ""))):
		return {"status": 403, "body": ""}
	if not _origin_allowed(str(headers.get("origin", ""))):
		return {"status": 403, "body": ""}

	if path == "/health":
		return _json_response(200, {"status": "ok", "server": SERVER_NAME, "version": SERVER_VERSION})
	if path != ENDPOINT:
		return {"status": 404, "body": ""}
	if method != "POST":
		return {"status": 405, "headers": {"Allow": "POST"}, "body": ""}

	var parsed = JSON.parse_string(body)
	if parsed == null:
		return _json_response(400, _error(null, -32700, "Parse error"))

	if parsed is Array:
		if parsed.is_empty():
			return _json_response(400, _error(null, -32600, "Invalid Request"))
		var replies := []
		for message in parsed:
			var reply = _handle_message(message)
			if reply != null:
				replies.append(reply)
		if replies.is_empty():
			return {"status": 202, "body": ""}
		return _json_response(200, replies)

	var single = _handle_message(parsed)
	if single == null:
		return {"status": 202, "body": ""}
	return _json_response(200, single)


## Returns a JSON-RPC response Dictionary, or null when nothing should be sent
## (notifications and client responses).
func _handle_message(message: Variant) -> Variant:
	if typeof(message) != TYPE_DICTIONARY:
		return _error(null, -32600, "Invalid Request")
	if not message.has("method"):
		if message.has("result") or message.has("error"):
			return null
		return _error(null, -32600, "Invalid Request")
	if not message.has("id"):
		return null  # notification, e.g. notifications/initialized

	var id = _normalize_id(message["id"])
	var method = message["method"]
	var params = message.get("params", {})
	if typeof(method) != TYPE_STRING:
		return _error(id, -32600, "Invalid Request")
	if typeof(params) != TYPE_DICTIONARY:
		params = {}

	match method:
		"initialize":
			return _ok(id, _initialize(params))
		"ping":
			return _ok(id, {})
		"tools/list":
			return _ok(id, {"tools": _registry.list_tools()})
		"tools/call":
			return _tools_call(id, params)
		_:
			return _error(id, -32601, "Method not found: %s" % method)


func _initialize(params: Dictionary) -> Dictionary:
	var requested := str(params.get("protocolVersion", ""))
	var version: String = requested if requested in SUPPORTED_VERSIONS else SUPPORTED_VERSIONS[0]
	return {
		"protocolVersion": version,
		"capabilities": {"tools": {"listChanged": false}},
		"serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
		"instructions": "Controls the running Godot editor. Start with the ping tool to confirm the connection.",
	}


func _tools_call(id: Variant, params: Dictionary) -> Dictionary:
	var tool_name := str(params.get("name", ""))
	if not _registry.has_tool(tool_name):
		return _error(id, -32602, "Unknown tool: %s" % tool_name)
	var arguments = params.get("arguments", {})
	if typeof(arguments) != TYPE_DICTIONARY:
		arguments = {}
	var outcome: Dictionary = _registry.call_tool(tool_name, arguments)
	return _ok(id, {
		"content": [{"type": "text", "text": outcome["text"]}],
		"isError": outcome["is_error"],
	})


# JSON parsing turns every number into a float (1 -> 1.0). Echo whole-number
# ids back as integers so strict clients still match them.
func _normalize_id(id: Variant) -> Variant:
	if typeof(id) == TYPE_FLOAT and id == floorf(id):
		return int(id)
	return id


func _host_allowed(host_header: String) -> bool:
	if host_header.is_empty():
		return true  # HTTP/1.0 style request without a Host header
	return host_header.split(":")[0] in LOCAL_HOSTS


func _origin_allowed(origin: String) -> bool:
	if origin.is_empty():
		return true  # non-browser clients (Claude Code, curl, mcp-remote) send no Origin
	var host := origin.trim_prefix("http://").trim_prefix("https://").split(":")[0]
	return host in LOCAL_HOSTS


func _ok(id: Variant, result: Variant) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


func _error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}


func _json_response(status: int, payload: Variant) -> Dictionary:
	return {
		"status": status,
		"headers": {"Content-Type": "application/json"},
		"body": JSON.stringify(payload),
	}
