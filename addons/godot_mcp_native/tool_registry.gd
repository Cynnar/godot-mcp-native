@tool
extends RefCounted
## Holds the tools exposed over MCP. Tool modules register themselves here.
##
## NOTE: a Callable does not keep a RefCounted object alive, so whoever creates
## a tool module must keep a reference to it (plugin.gd does).

var _tools := {}  # tool name -> {"description": String, "schema": Dictionary, "callable": Callable, "read_only": bool}

## When true, only tools registered as read-only can run.
var read_only_mode := false


## callable signature: func(arguments: Dictionary) -> Variant
## Return a Dictionary containing an "error" key to report a tool failure.
## read_only: pass true only for tools that never change the project, the open
## scene or the editor state. Everything else is blocked in read-only mode.
func add_tool(tool_name: String, description: String, input_schema: Dictionary, callable: Callable, read_only: bool = false) -> void:
	_tools[tool_name] = {
		"description": description,
		"schema": input_schema,
		"callable": callable,
		"read_only": read_only,
	}


func has_tool(tool_name: String) -> bool:
	return _tools.has(tool_name)


## Tool list in MCP "tools/list" format.
func list_tools() -> Array:
	var out := []
	for tool_name in _tools:
		var t: Dictionary = _tools[tool_name]
		out.append({
			"name": tool_name,
			"description": t["description"],
			"inputSchema": t["schema"],
			"annotations": {"readOnlyHint": t["read_only"]},
		})
	return out


## Runs a tool. Returns the tool's raw result (possibly an AsyncResult).
func call_tool(tool_name: String, arguments: Dictionary) -> Variant:
	var t: Dictionary = _tools[tool_name]
	if read_only_mode and not t["read_only"]:
		return {"error": "Read-only mode is on in the Godot MCP dock, so '%s' is blocked. Turn off \"Read-only mode\" in the MCP panel to allow changes." % tool_name}
	var callable: Callable = t["callable"]
	return callable.call(arguments)


## Turns a finished tool result into {"text": String, "is_error": bool, "image": Variant}.
## A result Dictionary may carry "_image": {"data": base64 String, "mime": String};
## it is removed from the text and returned separately as "image" (null if none).
func format_result(result: Variant) -> Dictionary:
	var image: Variant = null
	if typeof(result) == TYPE_DICTIONARY and result.has("_image"):
		result = result.duplicate()
		image = result["_image"]
		result.erase("_image")
	var is_error: bool = typeof(result) == TYPE_DICTIONARY and result.has("error")
	var text: String = result if typeof(result) == TYPE_STRING else JSON.stringify(result, "  ")
	return {"text": text, "is_error": is_error, "image": image}
