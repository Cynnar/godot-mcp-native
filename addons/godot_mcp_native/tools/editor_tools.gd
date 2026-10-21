@tool
extends RefCounted
## Read-only editor tools: scene info, node hierarchy and node properties.
## Node paths are always relative to the root of the scene being edited.

const Codec := preload("res://addons/godot_mcp_native/tools/variant_codec.gd")


func register(registry) -> void:
	registry.add_tool(
		"get_scene_info",
		"Describe the editor's current state: open scenes, the scene being edited, its root node, node count and whether a scene is running.",
		{"type": "object", "properties": {}},
		_get_scene_info
	)
	registry.add_tool(
		"get_hierarchy",
		"Return the node tree of the scene being edited. Each node has a name, type, path (relative to the scene root) and attached script, if any.",
		{
			"type": "object",
			"properties": {
				"root_path": {
					"type": "string",
					"description": "Node to start from, relative to the scene root. Default: the scene root (\".\").",
				},
				"max_depth": {
					"type": "integer",
					"description": "How many levels below the start node to include. Default 8.",
					"minimum": 0,
					"maximum": 32,
				},
			},
		},
		_get_hierarchy
	)
	registry.add_tool(
		"get_node_properties",
		"Return the editor-visible properties of a node in the scene being edited. Godot types such as Vector3 or Color are returned in Godot text form, e.g. \"Vector3(1, 2, 3)\".",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path of the node relative to the scene root. Use \".\" for the root itself.",
				},
				"names": {
					"type": "array",
					"items": {"type": "string"},
					"description": "Optional list of property names to return. Default: all editor-visible properties.",
				},
			},
			"required": ["node_path"],
		},
		_get_node_properties
	)


func _get_scene_info(_arguments: Dictionary) -> Dictionary:
	var open_scenes := []
	for scene_path in EditorInterface.get_open_scenes():
		open_scenes.append(scene_path)
	var info := {
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"open_scenes": open_scenes,
		"is_playing": EditorInterface.is_playing_scene(),
		"edited_scene": null,
	}
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		info["edited_scene"] = {
			"path": root.scene_file_path,
			"root_name": str(root.name),
			"root_type": root.get_class(),
			"node_count": _count_nodes(root),
		}
	return info


func _get_hierarchy(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var start_path := str(arguments.get("root_path", "."))
	var start := _find_node(root, start_path)
	if start == null:
		return {"error": "Node not found: '%s'. Paths are relative to the scene root." % start_path}
	var max_depth := clampi(int(arguments.get("max_depth", 8)), 0, 32)
	return {
		"scene": root.scene_file_path,
		"tree": _describe(start, root, 0, max_depth),
	}


func _get_node_properties(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var node_path := str(arguments.get("node_path", ""))
	var node := _find_node(root, node_path)
	if node == null:
		return {"error": "Node not found: '%s'. Use get_hierarchy to see valid paths." % node_path}

	var wanted = arguments.get("names", [])
	if typeof(wanted) != TYPE_ARRAY:
		wanted = []

	var properties := {}
	for prop_info in node.get_property_list():
		if (int(prop_info["usage"]) & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var prop_name: String = prop_info["name"]
		if not wanted.is_empty() and not wanted.has(prop_name):
			continue
		properties[prop_name] = Codec.to_json(node.get(prop_name))
	return {
		"path": str(root.get_path_to(node)),
		"type": node.get_class(),
		"properties": properties,
	}


func _find_node(root: Node, node_path: String) -> Node:
	if node_path.is_empty() or node_path == ".":
		return root
	return root.get_node_or_null(NodePath(node_path))


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _describe(node: Node, root: Node, depth: int, max_depth: int) -> Dictionary:
	var entry := {
		"name": str(node.name),
		"type": node.get_class(),
		"path": str(root.get_path_to(node)),
	}
	var script: Script = node.get_script()
	if script != null and not script.resource_path.is_empty():
		entry["script"] = script.resource_path
	if depth >= max_depth:
		if node.get_child_count() > 0:
			entry["child_count"] = node.get_child_count()
		return entry
	var children := []
	for child in node.get_children():
		children.append(_describe(child, root, depth + 1, max_depth))
	if not children.is_empty():
		entry["children"] = children
	return entry
