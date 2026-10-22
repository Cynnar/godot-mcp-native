@tool
extends RefCounted
## Project settings and the input map:
## list_project_settings, get_project_setting, set_project_setting,
## list_input_actions, add_input_action, remove_input_action.
##
## Changes are written to project.godot immediately. They are NOT undoable with
## Ctrl+Z (use git to revert).

const Codec := preload("res://addons/godot_mcp_native/tools/variant_codec.gd")
const Coerce := preload("res://addons/godot_mcp_native/tools/value_coerce.gd")

## Settings the plugin itself depends on; tools may not change them.
const PROTECTED_SETTINGS := ["autoload/GodotMcpNativeBridge", "editor_plugins/enabled"]
const MAX_LISTED := 300

const MOUSE_BUTTONS := {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP,
	"wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
}


func register(registry) -> void:
	registry.add_tool(
		"list_project_settings",
		"List project settings whose name starts with a prefix (e.g. \"application/\", \"display/window/\", \"physics/\"). Returns names and current values. Use \"\" to list top-level sections only.",
		{
			"type": "object",
			"properties": {
				"prefix": {"type": "string", "description": "Setting path prefix, e.g. display/window. Default: list the top-level sections."},
			},
		},
		_list_project_settings,
		true
	)
	registry.add_tool(
		"get_project_setting",
		"Read one project setting, e.g. application/config/name or display/window/size/viewport_width.",
		{
			"type": "object",
			"properties": {"name": {"type": "string", "description": "Full setting path."}},
			"required": ["name"],
		},
		_get_project_setting,
		true
	)
	registry.add_tool(
		"set_project_setting",
		"Change a project setting and save project.godot. The value is converted to the type the setting already has (Godot text form such as \"Vector2i(1280, 720)\" works for types JSON cannot express). Unknown settings are refused unless create is true. Not undoable with Ctrl+Z.",
		{
			"type": "object",
			"properties": {
				"name": {"type": "string", "description": "Full setting path."},
				"value": {"description": "The new value."},
				"create": {"type": "boolean", "description": "Allow creating a setting that does not exist yet (custom settings). Default false."},
			},
			"required": ["name", "value"],
		},
		_set_project_setting
	)
	registry.add_tool(
		"list_input_actions",
		"List the project's input actions (Project Settings > Input Map) with their events.",
		{
			"type": "object",
			"properties": {
				"include_builtin": {"type": "boolean", "description": "Also list Godot's built-in ui_* actions. Default false."},
			},
		},
		_list_input_actions,
		true
	)
	registry.add_tool(
		"add_input_action",
		"Add an input action to the project, or replace an existing custom one with replace: true. Events are strings: \"key:Space\", \"key:W\", \"key:Ctrl+S\" (physical keys; modifiers ctrl/shift/alt/meta), \"mouse:left\" (left, right, middle, wheel_up, wheel_down), \"joy_button:0\", \"joy_axis:0:-1\" (axis index and direction -1 or 1). Saves project.godot. Not undoable with Ctrl+Z.",
		{
			"type": "object",
			"properties": {
				"name": {"type": "string", "description": "Action name, e.g. jump or move_left."},
				"events": {"type": "array", "items": {"type": "string"}, "description": "Event strings, see the tool description. May be empty."},
				"deadzone": {"type": "number", "description": "Deadzone for analog input. Default 0.5."},
				"replace": {"type": "boolean", "description": "Replace the action if it already exists. Default false."},
			},
			"required": ["name"],
		},
		_add_input_action
	)
	registry.add_tool(
		"remove_input_action",
		"Remove a custom input action from the project. Built-in ui_* actions cannot be removed. Saves project.godot. Not undoable with Ctrl+Z.",
		{
			"type": "object",
			"properties": {"name": {"type": "string", "description": "Action name."}},
			"required": ["name"],
		},
		_remove_input_action
	)


func _list_project_settings(arguments: Dictionary) -> Dictionary:
	var prefix := str(arguments.get("prefix", "")).strip_edges()
	var sections := {}
	var settings := {}
	var truncated := false
	for prop_info in ProjectSettings.get_property_list():
		var setting_name: String = prop_info["name"]
		if not "/" in setting_name:
			continue
		if prefix.is_empty():
			sections[setting_name.get_slice("/", 0)] = true
		elif setting_name.begins_with(prefix):
			if settings.size() >= MAX_LISTED:
				truncated = true
				break
			settings[setting_name] = Codec.to_json(ProjectSettings.get_setting(setting_name))
	if prefix.is_empty():
		var names := sections.keys()
		names.sort()
		return {"sections": names, "hint": "Pass a prefix such as \"display/\" to list settings."}
	return {"prefix": prefix, "count": settings.size(), "settings": settings, "truncated": truncated}


func _get_project_setting(arguments: Dictionary) -> Dictionary:
	var setting_name := str(arguments.get("name", "")).strip_edges()
	if not ProjectSettings.has_setting(setting_name):
		return {"error": "No setting named '%s'. Use list_project_settings with a prefix to find it." % setting_name}
	return {"name": setting_name, "value": Codec.to_json(ProjectSettings.get_setting(setting_name))}


func _set_project_setting(arguments: Dictionary) -> Dictionary:
	var setting_name := str(arguments.get("name", "")).strip_edges()
	if not "/" in setting_name:
		return {"error": "Setting names look like section/name, e.g. application/config/name."}
	if setting_name in PROTECTED_SETTINGS or setting_name.begins_with("autoload/GodotMcpNative") or setting_name.begins_with("godot_mcp_native/"):
		return {"error": "'%s' is managed by the MCP plugin and can't be changed with this tool." % setting_name}
	if not arguments.has("value"):
		return {"error": "Missing 'value'."}

	var new_value: Variant = arguments["value"]
	if ProjectSettings.has_setting(setting_name):
		var current: Variant = ProjectSettings.get_setting(setting_name)
		var coerced := Coerce.to_type(typeof(current), new_value)
		if coerced.has("error"):
			return coerced
		new_value = coerced["value"]
	elif not bool(arguments.get("create", false)):
		return {"error": "No setting named '%s'. Check the name with list_project_settings, or pass create: true to add a new custom setting." % setting_name}

	ProjectSettings.set_setting(setting_name, new_value)
	var err := ProjectSettings.save()
	if err != OK:
		return {"error": "The value was set but saving project.godot failed: %s" % error_string(err)}
	return {"name": setting_name, "value": Codec.to_json(ProjectSettings.get_setting(setting_name)), "saved": true}


## Reads the project's actions from project settings (input/*). The editor's own
## InputMap also contains the editor's internal actions, which are not the user's.
func _list_input_actions(arguments: Dictionary) -> Dictionary:
	var include_builtin := bool(arguments.get("include_builtin", false))
	var actions := {}
	for prop_info in ProjectSettings.get_property_list():
		var setting_name: String = prop_info["name"]
		if not setting_name.begins_with("input/"):
			continue
		var action_name := setting_name.substr(6)
		if not include_builtin and action_name.begins_with("ui_"):
			continue
		var entry = ProjectSettings.get_setting(setting_name)
		if typeof(entry) == TYPE_DICTIONARY:
			actions[action_name] = _describe_action(entry)
	if include_builtin:
		for action in InputMap.get_actions():
			var builtin_name := str(action)
			if builtin_name.begins_with("ui_") and not actions.has(builtin_name):
				var events := []
				for event in InputMap.action_get_events(action):
					events.append(event.as_text())
				actions[builtin_name] = {"deadzone": InputMap.action_get_deadzone(action), "events": events, "builtin": true}
	return {"count": actions.size(), "actions": actions}


func _describe_action(entry: Dictionary) -> Dictionary:
	var events := []
	var raw_events = entry.get("events", [])
	if raw_events is Array:
		for event in raw_events:
			if event is InputEvent:
				events.append(event.as_text())
	return {"deadzone": entry.get("deadzone", 0.5), "events": events}


func _add_input_action(arguments: Dictionary) -> Dictionary:
	var action_name := str(arguments.get("name", "")).strip_edges()
	if action_name.is_empty() or "/" in action_name or "\"" in action_name:
		return {"error": "Action name must not be empty and must not contain / or quotes."}
	if action_name.begins_with("ui_"):
		return {"error": "Names starting with ui_ are reserved for Godot's built-in actions."}
	var setting_key := "input/" + action_name
	if ProjectSettings.has_setting(setting_key) and not bool(arguments.get("replace", false)):
		return {"error": "Action '%s' already exists. Pass replace: true to overwrite it." % action_name}

	var events: Array = []
	var raw_events = arguments.get("events", [])
	if not raw_events is Array:
		return {"error": "events must be an array of strings."}
	for raw in raw_events:
		var parsed := _parse_event(str(raw))
		if parsed.has("error"):
			return parsed
		events.append(parsed["event"])

	var deadzone := float(arguments.get("deadzone", 0.5))
	ProjectSettings.set_setting(setting_key, {"deadzone": deadzone, "events": events})
	var err := ProjectSettings.save()
	if err != OK:
		return {"error": "Saving project.godot failed: %s" % error_string(err)}
	return _list_one(action_name)


func _remove_input_action(arguments: Dictionary) -> Dictionary:
	var action_name := str(arguments.get("name", "")).strip_edges()
	var setting_key := "input/" + action_name
	if action_name.begins_with("ui_"):
		return {"error": "Built-in ui_* actions can't be removed."}
	if not ProjectSettings.has_setting(setting_key):
		return {"error": "No custom input action named '%s'." % action_name}
	ProjectSettings.set_setting(setting_key, null)
	var err := ProjectSettings.save()
	if err != OK:
		return {"error": "Saving project.godot failed: %s" % error_string(err)}
	return {"removed": action_name}


func _list_one(action_name: String) -> Dictionary:
	var entry = ProjectSettings.get_setting("input/" + action_name, {})
	var described := _describe_action(entry) if typeof(entry) == TYPE_DICTIONARY else {"events": []}
	return {"action": action_name, "events": described["events"], "saved": true}


## Parses "key:Ctrl+S", "mouse:left", "joy_button:0", "joy_axis:0:-1".
func _parse_event(spec: String) -> Dictionary:
	var kind := spec.get_slice(":", 0).strip_edges().to_lower()
	var rest := spec.substr(spec.find(":") + 1).strip_edges() if ":" in spec else ""
	if rest.is_empty():
		return {"error": "Invalid event '%s'. Examples: key:Space, mouse:left, joy_button:0, joy_axis:0:-1." % spec}

	if kind == "key":
		var event := InputEventKey.new()
		var parts := rest.split("+")
		var key_name := parts[parts.size() - 1].strip_edges()
		for i in parts.size() - 1:
			match parts[i].strip_edges().to_lower():
				"ctrl", "control":
					event.ctrl_pressed = true
				"shift":
					event.shift_pressed = true
				"alt":
					event.alt_pressed = true
				"meta", "cmd", "super":
					event.meta_pressed = true
				_:
					return {"error": "Unknown modifier '%s' in '%s'. Use ctrl, shift, alt or meta." % [parts[i], spec]}
		var code := OS.find_keycode_from_string(key_name)
		if code == KEY_NONE:
			return {"error": "Unknown key '%s' in '%s'. Use Godot key names such as Space, W, Enter, Escape, Left." % [key_name, spec]}
		event.physical_keycode = code
		return {"event": event}

	if kind == "mouse":
		var button_name := rest.to_lower()
		if not MOUSE_BUTTONS.has(button_name):
			return {"error": "Unknown mouse button '%s'. Use left, right, middle, wheel_up or wheel_down." % rest}
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = MOUSE_BUTTONS[button_name]
		return {"event": mouse_event}

	if kind == "joy_button":
		if not rest.is_valid_int():
			return {"error": "joy_button needs a number, e.g. joy_button:0."}
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = int(rest)
		return {"event": button_event}

	if kind == "joy_axis":
		var axis_parts := rest.split(":")
		if axis_parts.size() != 2 or not axis_parts[0].is_valid_int() or not axis_parts[1] in ["-1", "1", "+1"]:
			return {"error": "joy_axis needs an axis and a direction, e.g. joy_axis:0:-1."}
		var axis_event := InputEventJoypadMotion.new()
		axis_event.axis = int(axis_parts[0])
		axis_event.axis_value = float(int(axis_parts[1]))
		return {"event": axis_event}

	return {"error": "Unknown event type '%s'. Use key, mouse, joy_button or joy_axis." % kind}
