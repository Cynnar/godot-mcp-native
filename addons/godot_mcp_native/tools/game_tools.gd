@tool
extends RefCounted
## Tools that talk to the running game through the debugger bridge.

var _bridge


func register(registry, game_bridge) -> void:
	_bridge = game_bridge
	registry.add_tool(
		"get_game_screenshot",
		"Capture what the running game is currently drawing and return it as an image. The game must be running (play_scene) and was started from this editor. Wide screens are downscaled to max_width to keep the image small.",
		{
			"type": "object",
			"properties": {
				"max_width": {
					"type": "integer",
					"description": "Downscale so the image is at most this many pixels wide. Default 1024; 0 keeps the full size.",
					"minimum": 0,
					"maximum": 4096,
				},
			},
		},
		_get_game_screenshot,
		true
	)


func _get_game_screenshot(arguments: Dictionary) -> Variant:
	if not EditorInterface.is_playing_scene():
		return {"error": "No scene is running. Use play_scene first."}
	return _bridge.request_screenshot(clampi(int(arguments.get("max_width", 1024)), 0, 4096))
