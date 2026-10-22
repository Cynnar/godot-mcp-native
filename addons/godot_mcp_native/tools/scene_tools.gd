@tool
extends RefCounted
## Scene management: new_scene, open_scene, instantiate_scene, rename_node,
## reparent_node, duplicate_node, set_transform.
##
## Node edits go through undo/redo (Ctrl+Z in Godot reverts them). Creating or
## opening a scene is not undoable. Node paths are relative to the scene root.

const Codec := preload("res://addons/godot_mcp_native/tools/variant_codec.gd")

var _plugin: EditorPlugin


func register(registry, plugin: EditorPlugin) -> void:
	_plugin = plugin
	registry.add_tool(
		"new_scene",
		"Create a new scene file with a single root node, save it, and open it in the editor. Does not overwrite an existing file unless overwrite is true.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path ending in .tscn, e.g. res://scenes/level_1.tscn."},
				"root_type": {"type": "string", "description": "Godot node class for the root, e.g. Node2D, Node3D, Control. Default Node2D."},
				"root_name": {"type": "string", "description": "Optional root node name. Default: the file name in PascalCase."},
				"overwrite": {"type": "boolean", "description": "Replace the file if it exists. Default false."},
			},
			"required": ["path"],
		},
		_new_scene
	)
	registry.add_tool(
		"open_scene",
		"Open an existing scene in the editor (it becomes the scene the other tools edit). Unsaved changes in other open scenes are kept in their tabs.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path to a .tscn or .scn file."},
			},
			"required": ["path"],
		},
		_open_scene
	)
	registry.add_tool(
		"instantiate_scene",
		"Add an instance of another scene file as a child node in the scene being edited. Supports undo (Ctrl+Z).",
		{
			"type": "object",
			"properties": {
				"scene_path": {"type": "string", "description": "res:// path of the scene to instance."},
				"parent_path": {"type": "string", "description": "Parent node path relative to the scene root. Default: the root (\".\")."},
				"name": {"type": "string", "description": "Optional name for the new instance node."},
			},
			"required": ["scene_path"],
		},
		_instantiate_scene
	)
	registry.add_tool(
		"rename_node",
		"Rename a node in the scene being edited. Fails if a sibling already uses the name. The scene root cannot be renamed. Supports undo (Ctrl+Z).",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string", "description": "Node path relative to the scene root."},
				"new_name": {"type": "string", "description": "The new name (no . : / @ % characters)."},
			},
			"required": ["node_path", "new_name"],
		},
		_rename_node
	)
	registry.add_tool(
		"reparent_node",
		"Move a node (with its children) under a different parent. Supports undo (Ctrl+Z).",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string", "description": "Node path relative to the scene root."},
				"new_parent_path": {"type": "string", "description": "Path of the new parent, relative to the scene root."},
				"keep_global_transform": {"type": "boolean", "description": "Keep the node where it appears on screen/in the world. Default true."},
			},
			"required": ["node_path", "new_parent_path"],
		},
		_reparent_node
	)
	registry.add_tool(
		"duplicate_node",
		"Duplicate a node (with its children). The copy is placed right after the original under the same parent. The scene root cannot be duplicated. Supports undo (Ctrl+Z).",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string", "description": "Node path relative to the scene root."},
				"name": {"type": "string", "description": "Optional name for the copy. Default: Godot picks a unique name."},
			},
			"required": ["node_path"],
		},
		_duplicate_node
	)
	registry.add_tool(
		"set_transform",
		"Set position, rotation and/or scale of a Node2D or Node3D in one undoable step. Only the values you pass change. 2D: position [x, y], rotation in degrees (number), scale [x, y]. 3D: position [x, y, z], rotation in degrees [x, y, z], scale [x, y, z].",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string", "description": "Node path relative to the scene root."},
				"position": {"type": "array", "items": {"type": "number"}},
				"rotation": {"description": "Degrees. A number for 2D nodes, an [x, y, z] array for 3D nodes."},
				"scale": {"type": "array", "items": {"type": "number"}},
			},
			"required": ["node_path"],
		},
		_set_transform
	)


func _new_scene(arguments: Dictionary) -> Dictionary:
	var path := str(arguments.get("path", "")).strip_edges()
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		return {"error": "path must start with res:// and end with .tscn."}
	if path.begins_with("res://.godot") or path.begins_with("res://addons/godot_mcp_native/"):
		return {"error": "That location is not allowed."}
	if FileAccess.file_exists(path) and not bool(arguments.get("overwrite", false)):
		return {"error": "%s already exists. Pass overwrite: true to replace it, or use open_scene." % path}

	var type_name := str(arguments.get("root_type", "Node2D"))
	var creatable := ClassDB.class_exists(type_name) and ClassDB.is_parent_class(type_name, "Node") and ClassDB.can_instantiate(type_name)
	if not creatable:
		return {"error": "'%s' is not a node type that can be created." % type_name}

	var root: Node = ClassDB.instantiate(type_name)
	var root_name := str(arguments.get("root_name", ""))
	if root_name.is_empty():
		root_name = path.get_file().get_basename().to_pascal_case()
	if root_name.validate_node_name() != root_name or root_name.is_empty():
		root.free()
		return {"error": "root_name '%s' is not a valid node name." % root_name}
	root.name = root_name

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	root.free()
	if pack_err != OK:
		return {"error": "Could not pack the scene: %s" % error_string(pack_err)}

	var dir_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_err != OK:
		return {"error": "Could not create folder %s: %s" % [path.get_base_dir(), error_string(dir_err)]}
	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		return {"error": "Could not save %s: %s" % [path, error_string(save_err)]}

	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	return {"created": path, "root_type": type_name, "root_name": root_name}


func _open_scene(arguments: Dictionary) -> Dictionary:
	var path := str(arguments.get("path", "")).strip_edges()
	if not path.begins_with("res://") or not (path.ends_with(".tscn") or path.ends_with(".scn")):
		return {"error": "path must be a res:// path ending in .tscn or .scn."}
	if not ResourceLoader.exists(path):
		return {"error": "Scene not found: %s" % path}
	EditorInterface.open_scene_from_path(path)
	return {"opened": path}


func _instantiate_scene(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var scene_path := str(arguments.get("scene_path", "")).strip_edges()
	if not scene_path.begins_with("res://") or not (scene_path.ends_with(".tscn") or scene_path.ends_with(".scn")):
		return {"error": "scene_path must be a res:// path ending in .tscn or .scn."}
	if scene_path == root.scene_file_path:
		return {"error": "A scene can't be instanced inside itself."}
	if not ResourceLoader.exists(scene_path):
		return {"error": "Scene not found: %s" % scene_path}
	var packed = load(scene_path)
	if not packed is PackedScene:
		return {"error": "%s is not a scene." % scene_path}

	var parent_path := str(arguments.get("parent_path", "."))
	var parent := _find_node(root, parent_path)
	if parent == null:
		return {"error": "Parent node not found: '%s'. Use get_hierarchy to see valid paths." % parent_path}

	var instance: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if instance == null:
		return {"error": "Could not instantiate %s." % scene_path}
	var node_name := str(arguments.get("name", ""))
	if not node_name.is_empty():
		if node_name.validate_node_name() != node_name:
			instance.free()
			return {"error": "'%s' is not a valid node name." % node_name}
		instance.name = node_name

	var undo := _plugin.get_undo_redo()
	undo.create_action("Instantiate %s (AI)" % scene_path.get_file(), UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(parent, "add_child", instance, true)
	undo.add_do_method(instance, "set_owner", root)
	undo.add_do_reference(instance)
	undo.add_undo_method(parent, "remove_child", instance)
	undo.commit_action()

	return {"path": str(root.get_path_to(instance)), "name": str(instance.name), "scene": scene_path}


func _rename_node(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var node_path := str(arguments.get("node_path", ""))
	var node := _find_node(root, node_path)
	if node == null:
		return {"error": "Node not found: '%s'. Use get_hierarchy to see valid paths." % node_path}
	if node == root:
		return {"error": "The scene root can't be renamed with this tool."}

	var new_name := str(arguments.get("new_name", "")).strip_edges()
	if new_name.is_empty() or new_name.validate_node_name() != new_name:
		return {"error": "'%s' is not a valid node name (no . : / @ %% characters)." % new_name}
	var old_name := node.name
	if new_name == str(old_name):
		return {"path": str(root.get_path_to(node)), "name": new_name, "changed": false}
	var parent := node.get_parent()
	if parent.has_node(NodePath(new_name)):
		return {"error": "A sibling named '%s' already exists." % new_name}

	var undo := _plugin.get_undo_redo()
	undo.create_action("Rename %s (AI)" % old_name, UndoRedo.MERGE_DISABLE, root)
	undo.add_do_property(node, "name", StringName(new_name))
	undo.add_undo_property(node, "name", old_name)
	undo.commit_action()

	return {"path": str(root.get_path_to(node)), "name": str(node.name), "old_name": str(old_name)}


func _reparent_node(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var node_path := str(arguments.get("node_path", ""))
	var node := _find_node(root, node_path)
	if node == null:
		return {"error": "Node not found: '%s'. Use get_hierarchy to see valid paths." % node_path}
	if node == root:
		return {"error": "The scene root can't be moved."}
	var new_parent_path := str(arguments.get("new_parent_path", ""))
	var new_parent := _find_node(root, new_parent_path)
	if new_parent == null:
		return {"error": "New parent not found: '%s'." % new_parent_path}
	if new_parent == node or node.is_ancestor_of(new_parent):
		return {"error": "A node can't be moved into itself or its own children."}
	var old_parent := node.get_parent()
	if new_parent == old_parent:
		return {"error": "'%s' is already a child of '%s'." % [node_path, new_parent_path]}
	if new_parent.has_node(NodePath(str(node.name))):
		return {"error": "'%s' already has a child named '%s'. Rename the node first." % [new_parent_path, node.name]}

	var keep := bool(arguments.get("keep_global_transform", true))
	var old_index := node.get_index()
	var owned: Array[Node] = []
	_collect_owned(node, root, owned)

	# reparent() can drop owners, so restore them after each move.
	var undo := _plugin.get_undo_redo()
	undo.create_action("Reparent %s (AI)" % node.name, UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(node, "reparent", new_parent, keep)
	for owned_node in owned:
		undo.add_do_method(owned_node, "set_owner", root)
	undo.add_undo_method(node, "reparent", old_parent, keep)
	undo.add_undo_method(old_parent, "move_child", node, old_index)
	for owned_node in owned:
		undo.add_undo_method(owned_node, "set_owner", root)
	undo.commit_action()

	return {"path": str(root.get_path_to(node)), "parent": new_parent_path if new_parent != root else "."}


func _duplicate_node(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var node_path := str(arguments.get("node_path", ""))
	var node := _find_node(root, node_path)
	if node == null:
		return {"error": "Node not found: '%s'. Use get_hierarchy to see valid paths." % node_path}
	if node == root:
		return {"error": "The scene root can't be duplicated."}
	var new_name := str(arguments.get("name", "")).strip_edges()
	if not new_name.is_empty() and new_name.validate_node_name() != new_name:
		return {"error": "'%s' is not a valid node name." % new_name}

	var parent := node.get_parent()
	if not new_name.is_empty() and parent.has_node(NodePath(new_name)):
		return {"error": "A sibling named '%s' already exists." % new_name}

	var copy := node.duplicate()
	if copy == null:
		return {"error": "Duplicating failed."}
	if not new_name.is_empty():
		copy.name = new_name

	# Nodes owned by the scene root in the original must be owned by it in the copy.
	var owned: Array[Node] = []
	_collect_owned(node, root, owned)
	var copy_owned: Array[Node] = []
	for owned_node in owned:
		var rel := node.get_path_to(owned_node)
		var counterpart := copy if str(rel) == "." else copy.get_node_or_null(rel)
		if counterpart != null:
			copy_owned.append(counterpart)

	var undo := _plugin.get_undo_redo()
	undo.create_action("Duplicate %s (AI)" % node.name, UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(parent, "add_child", copy, true)
	undo.add_do_method(parent, "move_child", copy, node.get_index() + 1)
	for copy_node in copy_owned:
		undo.add_do_method(copy_node, "set_owner", root)
	undo.add_do_reference(copy)
	undo.add_undo_method(parent, "remove_child", copy)
	undo.commit_action()

	return {"path": str(root.get_path_to(copy)), "name": str(copy.name), "copied_from": node_path}


func _set_transform(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var node_path := str(arguments.get("node_path", ""))
	var node := _find_node(root, node_path)
	if node == null:
		return {"error": "Node not found: '%s'. Use get_hierarchy to see valid paths." % node_path}

	var is_2d := node is Node2D
	var is_3d := node is Node3D
	if not is_2d and not is_3d:
		return {"error": "'%s' is a %s, not a Node2D or Node3D." % [node_path, node.get_class()]}
	if not (arguments.has("position") or arguments.has("rotation") or arguments.has("scale")):
		return {"error": "Pass at least one of position, rotation or scale."}

	var changes := {}  # property name -> new value
	if arguments.has("position"):
		var v: Variant = _vector(arguments["position"], 2 if is_2d else 3)
		if v == null:
			return {"error": "position must be an array of %d numbers." % (2 if is_2d else 3)}
		changes["position"] = v
	if arguments.has("scale"):
		var v: Variant = _vector(arguments["scale"], 2 if is_2d else 3)
		if v == null:
			return {"error": "scale must be an array of %d numbers." % (2 if is_2d else 3)}
		changes["scale"] = v
	if arguments.has("rotation"):
		var rot = arguments["rotation"]
		if is_2d:
			if typeof(rot) not in [TYPE_INT, TYPE_FLOAT]:
				return {"error": "rotation for a 2D node must be a number (degrees)."}
			changes["rotation_degrees"] = float(rot)
		else:
			var v: Variant = _vector(rot, 3)
			if v == null:
				return {"error": "rotation for a 3D node must be an array of 3 numbers (degrees)."}
			changes["rotation_degrees"] = v

	var undo := _plugin.get_undo_redo()
	undo.create_action("Transform %s (AI)" % node.name, UndoRedo.MERGE_DISABLE, root)
	for prop_name in changes:
		undo.add_do_property(node, prop_name, changes[prop_name])
		undo.add_undo_property(node, prop_name, node.get(prop_name))
	undo.commit_action()

	var result := {"path": str(root.get_path_to(node))}
	for prop_name in changes:
		result[prop_name] = Codec.to_json(node.get(prop_name))
	return result


## Converts [x, y] / [x, y, z] to Vector2 / Vector3, or null when invalid.
func _vector(value: Variant, size: int) -> Variant:
	if not value is Array or value.size() != size:
		return null
	for item in value:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT]:
			return null
	if size == 2:
		return Vector2(value[0], value[1])
	return Vector3(value[0], value[1], value[2])


func _find_node(root: Node, node_path: String) -> Node:
	if node_path.is_empty() or node_path == ".":
		return root
	return root.get_node_or_null(NodePath(node_path))


func _collect_owned(node: Node, root: Node, out: Array[Node]) -> void:
	if node.owner == root:
		out.append(node)
	for child in node.get_children():
		_collect_owned(child, root, out)
