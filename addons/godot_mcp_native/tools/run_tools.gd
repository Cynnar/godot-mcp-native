@tool
extends RefCounted
## Run control and log access: play_scene, stop_scene, get_output_log.

var _log


func register(registry, log_capture) -> void:
	_log = log_capture
	registry.add_tool(
		"play_scene",
		"Run a scene in the editor. With no scene_path the scene being edited runs (it must have been saved); \"main\" runs the project's main scene; a res:// path runs that scene. Running saves open scenes first. The game starts asynchronously, so check get_scene_info (is_playing) to confirm.",
		{
			"type": "object",
			"properties": {
				"scene_path": {
					"type": "string",
					"description": "Optional: \"main\" or a res:// path to a .tscn/.scn file. Default: the scene being edited.",
				},
			},
		},
		_play_scene
	)
	registry.add_tool(
		"stop_scene",
		"Stop the running scene. Does nothing (and says so) if nothing is running.",
		{"type": "object", "properties": {}},
		_stop_scene
	)
	registry.add_tool(
		"get_output_log",
		"Read recent messages logged by the Godot editor process: print() output and push_error/push_warning from @tool scripts, script compile errors, and editor errors. It does NOT include output from the running game, which is a separate process. Each entry has an id; pass the latest_id you got last time as since_id to read only newer entries.",
		{
			"type": "object",
			"properties": {
				"level": {
					"type": "string",
					"enum": ["all", "error", "warning", "info"],
					"description": "Only return entries of this level. Default all.",
				},
				"max_entries": {
					"type": "integer",
					"description": "Return at most this many of the most recent entries. Default 100, max 1000.",
					"minimum": 1,
					"maximum": 1000,
				},
				"since_id": {
					"type": "integer",
					"description": "Only return entries with an id greater than this. Default 0 (everything buffered).",
					"minimum": 0,
				},
				"clear": {
					"type": "boolean",
					"description": "Empty the buffer after reading. Default false.",
				},
			},
		},
		_get_output_log
	)


func _play_scene(arguments: Dictionary) -> Dictionary:
	if EditorInterface.is_playing_scene():
		return {"error": "A scene is already running. Call stop_scene first."}

	var target := str(arguments.get("scene_path", "")).strip_edges()
	if target.is_empty():
		var root := EditorInterface.get_edited_scene_root()
		if root == null:
			return {"error": "No scene is open in the editor."}
		if root.scene_file_path.is_empty():
			return {"error": "The scene has never been saved. Use save_scene with a res:// path first, then run it."}
		EditorInterface.play_current_scene()
		return {"started": root.scene_file_path}

	if target == "main":
		var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
		if main_scene.is_empty():
			return {"error": "The project has no main scene configured (Project Settings > Application > Run)."}
		EditorInterface.play_main_scene()
		return {"started": main_scene}

	if not target.begins_with("res://") or not (target.ends_with(".tscn") or target.ends_with(".scn")):
		return {"error": "scene_path must be \"main\" or a res:// path ending in .tscn or .scn."}
	if not ResourceLoader.exists(target):
		return {"error": "Scene not found: %s" % target}
	EditorInterface.play_custom_scene(target)
	return {"started": target}


func _stop_scene(_arguments: Dictionary) -> Dictionary:
	var was_playing := EditorInterface.is_playing_scene()
	if was_playing:
		EditorInterface.stop_playing_scene()
	return {"was_playing": was_playing}


func _get_output_log(arguments: Dictionary) -> Dictionary:
	var level := str(arguments.get("level", "all"))
	if not level in ["all", "error", "warning", "info"]:
		return {"error": "level must be one of: all, error, warning, info."}
	var max_entries := clampi(int(arguments.get("max_entries", 100)), 1, 1000)
	var since_id := maxi(0, int(arguments.get("since_id", 0)))

	var entries: Array = _log.read(since_id, level, max_entries)
	var result := {
		"entries": entries,
		"count": entries.size(),
		"latest_id": _log.last_id(),
		"scope": "editor process only (not the running game)",
	}
	if bool(arguments.get("clear", false)):
		_log.clear()
	return result
