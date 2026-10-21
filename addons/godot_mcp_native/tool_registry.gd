@tool
extends RefCounted
## Holds the tools exposed over MCP. Tool modules register themselves here.
##
## NOTE: a Callable does not keep a RefCounted object alive, so whoever creates
## a tool module must keep a reference to it (plugin.gd does).

var _tools := {}  # tool name -> {"description": String, "schema": Dictionary, "callable": Callable}


## callable signature: func(arguments: Dictionary) -> Variant
## Return a Dictionary containing an "error" key to report a tool failure.
func add_tool(tool_name: String, description: String, input_schema: Dictionary, callable: Callable) -> void:
	_tools[tool_name] = {
		"description": description,
		"schema": input_schema,
		"callable": callable,
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
		})
	return out


## Runs a tool. Returns the tool's raw result (possibly an AsyncResult).
func call_tool(tool_name: String, arguments: Dictionary) -> Variant:
	var t: Dictionary = _tools[tool_name]
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
