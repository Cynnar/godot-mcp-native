@tool
extends RefCounted
## Editor tools that change the scene being edited.
##
## Every change goes through the editor's undo/redo system, so Ctrl+Z in Godot
## reverts what the AI client did. Node paths are relative to the scene root.

const Codec := preload("res://addons/godot_mcp_native/tools/variant_codec.gd")

var _plugin: EditorPlugin


func register(registry, plugin: EditorPlugin) -> void:
	_plugin = plugin
	registry.add_tool(
		"create_node",
		"Create a node in the scene being edited. Supports undo (Ctrl+Z).",
		{
			"type": "object",
			"properties": {
				"type": {
					"type": "string",
					"description": "Godot node class, e.g. Node2D, Sprite2D, CharacterBody3D, Label.",
				},
				"parent_path": {
					"type": "string",
					"description": "Parent node path relative to the scene root. Default: the scene root (\".\").",
				},
				"name": {
					"type": "string",
					"description": "Optional node name. Godot makes it unique if it is already taken.",
				},
				"properties": {
					"type": "object",
					"description": "Optional initial property values, same value rules as set_property.",
				},
			},
			"required": ["type"],
		},
		_create_node
	)
	registry.add_tool(
		"set_property",
		"Set a property on a node in the scene being edited. Supports undo (Ctrl+Z). Values for Godot types may be given in Godot text form (\"Vector2(10, 20)\", \"Color(1, 0, 0, 1)\"); Vector2, Vector3 and Color also accept JSON arrays like [10, 20]. Resource properties accept a \"res://\" path.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Node path relative to the scene root. Use \".\" for the root.",
				},
				"property": {"type": "string", "description": "Property name, e.g. position, visible, texture."},
				"value": {"description": "The new value."},
			},
			"required": ["node_path", "property", "value"],
		},
		_set_property
	)
	registry.add_tool(
		"delete_node",
		"Delete a node (and its children) from the scene being edited. The scene root cannot be deleted. Supports undo (Ctrl+Z).",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string", "description": "Node path relative to the scene root."},
			},
			"required": ["node_path"],
		},
		_delete_node
	)
	registry.add_tool(
		"save_scene",
		"Save the scene being edited. If the scene has never been saved, pass a res:// path ending in .tscn.",
		{
			"type": "object",
			"properties": {
				"path": {
					"type": "string",
					"description": "Optional res:// path ending in .tscn. Required only for a scene that has never been saved.",
				},
			},
		},
		_save_scene
	)


func _create_node(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}

	var type_name := str(arguments.get("type", ""))
	var creatable := ClassDB.class_exists(type_name) and ClassDB.is_parent_class(type_name, "Node") and ClassDB.can_instantiate(type_name)
	if not creatable:
		return {"error": "'%s' is not a node type that can be created. Use a Godot class name such as Node2D, Sprite2D or Label." % type_name}

	var parent_path := str(arguments.get("parent_path", "."))
	var parent := _find_node(root, parent_path)
	if parent == null:
		return {"error": "Parent node not found: '%s'. Use get_hierarchy to see valid paths." % parent_path}

	var node: Node = ClassDB.instantiate(type_name)
	var node_name := str(arguments.get("name", ""))
	if not node_name.is_empty():
		node.name = node_name

	var initial = arguments.get("properties", {})
	if typeof(initial) == TYPE_DICTIONARY:
		for prop_name in initial:
			var coerced := _coerce(node, str(prop_name), initial[prop_name])
			if coerced.has("error"):
				node.free()
				return coerced
			node.set(str(prop_name), coerced["value"])

	var undo := _plugin.get_undo_redo()
	undo.create_action("Create %s (AI)" % type_name, UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(parent, "add_child", node, true)
	undo.add_do_method(node, "set_owner", root)
	undo.add_do_reference(node)
	undo.add_undo_method(parent, "remove_child", node)
	undo.commit_action()

	return {
		"path": str(root.get_path_to(node)),
		"name": str(node.name),
		"type": node.get_class(),
	}


func _set_property(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var node_path := str(arguments.get("node_path", ""))
	var node := _find_node(root, node_path)
	if node == null:
		return {"error": "Node not found: '%s'. Use get_hierarchy to see valid paths." % node_path}
	if not arguments.has("value"):
		return {"error": "Missing 'value'."}

	var prop_name := str(arguments.get("property", ""))
	var coerced := _coerce(node, prop_name, arguments["value"])
	if coerced.has("error"):
		return coerced

	var old_value = node.get(prop_name)
	var undo := _plugin.get_undo_redo()
	undo.create_action("Set %s.%s (AI)" % [node.name, prop_name], UndoRedo.MERGE_DISABLE, root)
	undo.add_do_property(node, prop_name, coerced["value"])
	undo.add_undo_property(node, prop_name, old_value)
	undo.commit_action()

	return {
		"path": str(root.get_path_to(node)),
		"property": prop_name,
		"value": Codec.to_json(node.get(prop_name)),
	}


func _delete_node(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var node_path := str(arguments.get("node_path", ""))
	var node := _find_node(root, node_path)
	if node == null:
		return {"error": "Node not found: '%s'. Use get_hierarchy to see valid paths." % node_path}
	if node == root:
		return {"error": "The scene root can't be deleted."}

	var parent := node.get_parent()
	var index := node.get_index()
	var removed_path := str(root.get_path_to(node))

	# Removing a node can drop its owner, so remember which nodes belong to the
	# scene and restore that on undo (parents come before children).
	var owned: Array[Node] = []
	_collect_owned(node, root, owned)

	var undo := _plugin.get_undo_redo()
	undo.create_action("Delete %s (AI)" % node.name, UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(parent, "remove_child", node)
	undo.add_undo_method(parent, "add_child", node, true)
	undo.add_undo_method(parent, "move_child", node, index)
	for owned_node in owned:
		undo.add_undo_method(owned_node, "set_owner", root)
	undo.add_undo_reference(node)
	undo.commit_action()

	return {"deleted": removed_path}


func _save_scene(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}

	var path := str(arguments.get("path", ""))
	if path.is_empty():
		if root.scene_file_path.is_empty():
			return {"error": "This scene has never been saved. Pass a path such as res://scenes/level.tscn."}
		var err := EditorInterface.save_scene()
		if err != OK:
			return {"error": "Saving failed: %s" % error_string(err)}
		return {"saved": root.scene_file_path}

	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		return {"error": "Path must start with res:// and end with .tscn."}
	EditorInterface.save_scene_as(path)
	return {"saved": path}


## Converts a JSON value to what the property expects. Returns {"value": ...}
## on success or {"error": ...} on failure.
func _coerce(node: Node, prop_name: String, value: Variant) -> Dictionary:
	var expected := -1
	for prop_info in node.get_property_list():
		if prop_info["name"] == prop_name:
			expected = int(prop_info["type"])
			break
	if expected < 0:
		return {"error": "Node '%s' (%s) has no property '%s'. Use get_node_properties to see valid names." % [node.name, node.get_class(), prop_name]}

	match expected:
		TYPE_STRING:
			return {"value": str(value)}
		TYPE_STRING_NAME:
			return {"value": StringName(str(value))}
		TYPE_NODE_PATH:
			return {"value": NodePath(str(value))}
		TYPE_BOOL:
			if typeof(value) == TYPE_BOOL:
				return {"value": value}
		TYPE_INT:
			if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
				return {"value": int(value)}
		TYPE_FLOAT:
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				return {"value": float(value)}
		TYPE_VECTOR2:
			if value is Array and value.size() == 2:
				return {"value": Vector2(value[0], value[1])}
		TYPE_VECTOR3:
			if value is Array and value.size() == 3:
				return {"value": Vector3(value[0], value[1], value[2])}
		TYPE_COLOR:
			if value is Array and value.size() == 3:
				return {"value": Color(value[0], value[1], value[2])}
			if value is Array and value.size() == 4:
				return {"value": Color(value[0], value[1], value[2], value[3])}
		TYPE_OBJECT:
			if value == null:
				return {"value": null}
			if typeof(value) == TYPE_STRING and str(value).begins_with("res://"):
				var resource := load(str(value))
				if resource == null:
					return {"error": "Could not load resource '%s'." % str(value)}
				return {"value": resource}

	# Everything else arrives in Godot text form, e.g. "Rect2(0, 0, 10, 10)".
	if typeof(value) == TYPE_STRING:
		var parsed = str_to_var(value)
		if parsed == null and str(value).strip_edges() != "null":
			return {"error": "Could not parse '%s' as %s. Use Godot text form such as Vector2(1, 2) or Color(1, 0, 0, 1)." % [value, type_string(expected)]}
		return {"value": parsed}
	return {"value": value}


func _find_node(root: Node, node_path: String) -> Node:
	if node_path.is_empty() or node_path == ".":
		return root
	return root.get_node_or_null(NodePath(node_path))


func _collect_owned(node: Node, root: Node, out: Array[Node]) -> void:
	if node.owner == root:
		out.append(node)
	for child in node.get_children():
		_collect_owned(child, root, out)
