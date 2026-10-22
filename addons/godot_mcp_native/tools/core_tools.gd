@tool
extends RefCounted
## Basic tools: connectivity check and engine/project info.


func register(registry) -> void:
	registry.add_tool(
		"ping",
		"Check that the Godot editor is reachable. Returns the Godot version and the open project's name.",
		{"type": "object", "properties": {}},
		_ping,
		true
	)


func _ping(_arguments: Dictionary) -> Dictionary:
	var info := Engine.get_version_info()
	return {
		"pong": true,
		"godot_version": info.get("string", "unknown"),
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"plugin": "godot-mcp-native",
	}
