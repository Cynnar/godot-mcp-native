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


## Runs a tool. Returns {"text": String, "is_error": bool}.
func call_tool(tool_name: String, arguments: Dictionary) -> Dictionary:
	var t: Dictionary = _tools[tool_name]
	var callable: Callable = t["callable"]
	var result = callable.call(arguments)
	var is_error: bool = typeof(result) == TYPE_DICTIONARY and result.has("error")
	var text: String = result if typeof(result) == TYPE_STRING else JSON.stringify(result, "  ")
	return {"text": text, "is_error": is_error}
