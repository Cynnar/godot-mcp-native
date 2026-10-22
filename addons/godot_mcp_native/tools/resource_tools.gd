@tool
extends RefCounted
## Resources and project files: list_files, create_resource,
## get_resource_properties, set_resource_property.
##
## Resource files are written directly (not undoable with Ctrl+Z; use git).

const Codec := preload("res://addons/godot_mcp_native/tools/variant_codec.gd")
const Coerce := preload("res://addons/godot_mcp_native/tools/value_coerce.gd")

const PROTECTED_PREFIX := "res://addons/godot_mcp_native/"
const MAX_FILES := 500


func register(registry) -> void:
	registry.add_tool(
		"list_files",
		"List files in the project (assets, scenes, resources, ...). Hidden folders such as .godot are skipped.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// folder to list. Default res://."},
				"extensions": {"type": "array", "items": {"type": "string"}, "description": "Only files with these extensions, e.g. [\"png\", \"tres\"]. Default: all."},
				"recursive": {"type": "boolean", "description": "Include subfolders. Default true."},
			},
		},
		_list_files,
		true
	)
	registry.add_tool(
		"create_resource",
		"Create a new resource file (.tres) of a built-in Resource type, e.g. StandardMaterial3D, LabelSettings, Gradient, RectangleShape2D, Theme. Optional initial properties use the same value rules as set_property. Does not overwrite unless overwrite is true.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path ending in .tres."},
				"type": {"type": "string", "description": "Godot Resource class name."},
				"properties": {"type": "object", "description": "Optional initial property values."},
				"overwrite": {"type": "boolean", "description": "Replace the file if it exists. Default false."},
			},
			"required": ["path", "type"],
		},
		_create_resource
	)
	registry.add_tool(
		"get_resource_properties",
		"Read the editable properties of a resource file (.tres/.res) such as a material or theme.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path of the resource."},
				"names": {"type": "array", "items": {"type": "string"}, "description": "Optional: only these properties."},
			},
			"required": ["path"],
		},
		_get_resource_properties,
		true
	)
	registry.add_tool(
		"set_resource_property",
		"Set a property on a resource file (.tres) and save it. Same value rules as set_property (Godot text form, arrays for Vector/Color, res:// paths for resources). Not undoable with Ctrl+Z.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path ending in .tres."},
				"property": {"type": "string"},
				"value": {"description": "The new value."},
			},
			"required": ["path", "property", "value"],
		},
		_set_resource_property
	)


func _list_files(arguments: Dictionary) -> Dictionary:
	var base := str(arguments.get("path", "res://")).strip_edges()
	if not base.begins_with("res://"):
		return {"error": "path must start with res://."}
	if not DirAccess.dir_exists_absolute(base):
		return {"error": "Folder not found: %s" % base}
	var wanted: Array = []
	var raw_ext = arguments.get("extensions", [])
	if raw_ext is Array:
		for e in raw_ext:
			wanted.append(str(e).trim_prefix(".").to_lower())
	var files: Array = []
	var state := {"truncated": false}
	_walk(base, wanted, bool(arguments.get("recursive", true)), files, state)
	files.sort()
	return {"path": base, "count": files.size(), "files": files, "truncated": state["truncated"]}


func _walk(dir_path: String, wanted: Array, recursive: bool, out: Array, state: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				if recursive:
					_walk(full, wanted, recursive, out, state)
			elif wanted.is_empty() or entry.get_extension().to_lower() in wanted:
				if out.size() >= MAX_FILES:
					state["truncated"] = true
					return
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _create_resource(arguments: Dictionary) -> Dictionary:
	var path := str(arguments.get("path", "")).strip_edges()
	var path_error := _check_tres_path(path)
	if not path_error.is_empty():
		return {"error": path_error}
	if FileAccess.file_exists(path) and not bool(arguments.get("overwrite", false)):
		return {"error": "%s already exists. Pass overwrite: true to replace it." % path}

	var type_name := str(arguments.get("type", ""))
	var creatable := ClassDB.class_exists(type_name) and ClassDB.is_parent_class(type_name, "Resource") and ClassDB.can_instantiate(type_name)
	if not creatable:
		return {"error": "'%s' is not a Resource type that can be created. Use a class name such as StandardMaterial3D or LabelSettings." % type_name}

	var resource: Resource = ClassDB.instantiate(type_name)
	var initial = arguments.get("properties", {})
	if typeof(initial) == TYPE_DICTIONARY:
		for prop_name in initial:
			var coerced := Coerce.property(resource, str(prop_name), initial[prop_name])
			if coerced.has("error"):
				return coerced
			resource.set(str(prop_name), coerced["value"])

	var dir_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_err != OK:
		return {"error": "Could not create folder %s: %s" % [path.get_base_dir(), error_string(dir_err)]}
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		return {"error": "Could not save %s: %s" % [path, error_string(err)]}
	EditorInterface.get_resource_filesystem().scan()
	return {"created": path, "type": type_name}


func _get_resource_properties(arguments: Dictionary) -> Dictionary:
	var path := str(arguments.get("path", "")).strip_edges()
	var loaded := _load_resource(path)
	if loaded.has("error"):
		return loaded
	var resource: Resource = loaded["resource"]

	var only: Array = []
	var raw_names = arguments.get("names", [])
	if raw_names is Array:
		for n in raw_names:
			only.append(str(n))
	var props := {}
	for prop_info in resource.get_property_list():
		if not (int(prop_info["usage"]) & PROPERTY_USAGE_EDITOR):
			continue
		var prop_name: String = prop_info["name"]
		if only.is_empty() or prop_name in only:
			props[prop_name] = Codec.to_json(resource.get(prop_name))
	return {"path": path, "type": resource.get_class(), "properties": props}


func _set_resource_property(arguments: Dictionary) -> Dictionary:
	var path := str(arguments.get("path", "")).strip_edges()
	var path_error := _check_tres_path(path)
	if not path_error.is_empty():
		return {"error": path_error}
	var loaded := _load_resource(path)
	if loaded.has("error"):
		return loaded
	var resource: Resource = loaded["resource"]
	if not arguments.has("value"):
		return {"error": "Missing 'value'."}

	var prop_name := str(arguments.get("property", ""))
	var coerced := Coerce.property(resource, prop_name, arguments["value"])
	if coerced.has("error"):
		return coerced
	resource.set(prop_name, coerced["value"])
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		return {"error": "Could not save %s: %s" % [path, error_string(err)]}
	return {"path": path, "property": prop_name, "value": Codec.to_json(resource.get(prop_name)), "saved": true}


func _load_resource(path: String) -> Dictionary:
	if not path.begins_with("res://"):
		return {"error": "path must start with res://."}
	if not ResourceLoader.exists(path):
		return {"error": "Resource not found: %s" % path}
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		return {"error": "Could not load %s." % path}
	if resource is PackedScene or resource is Script:
		return {"error": "%s is a scene or script. Use the scene/script tools for those." % path}
	return {"resource": resource}


## Returns an error message, or "" when the path is usable for writing.
func _check_tres_path(path: String) -> String:
	if not path.begins_with("res://") or not path.ends_with(".tres"):
		return "path must start with res:// and end with .tres."
	if path.begins_with("res://.godot") or path.begins_with(PROTECTED_PREFIX):
		return "That location is not allowed."
	return ""
