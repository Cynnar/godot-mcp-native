@tool
extends RefCounted
## GDScript file tools: list, view, create, update, edit and attach scripts.
##
## Script files are written straight to disk, so those changes are NOT part of
## the editor's scene undo history. Use version control to roll them back.
## Only attach_script goes through undo/redo (it changes a node).

const PROTECTED_PREFIX := "res://addons/godot_mcp_native/"
const MAX_LIST_RESULTS := 1000
const DEFAULT_VIEW_LINES := 2000

var _plugin: EditorPlugin
var _log  # optional LogCapture, used to report compile errors


func register(registry, plugin: EditorPlugin, log_capture = null) -> void:
	_plugin = plugin
	_log = log_capture
	registry.add_tool(
		"list_scripts",
		"List the GDScript (.gd) files in the project. Addons are skipped unless include_addons is true.",
		{
			"type": "object",
			"properties": {
				"include_addons": {"type": "boolean", "description": "Also list scripts under res://addons. Default false."},
			},
		},
		_list_scripts,
		true
	)
	registry.add_tool(
		"view_script",
		"Read a GDScript file. Returns up to 2000 lines starting at start_line; use start_line/end_line to page through longer files.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path of the .gd file."},
				"start_line": {"type": "integer", "description": "First line to return (1-based). Default 1.", "minimum": 1},
				"end_line": {"type": "integer", "description": "Last line to return (inclusive). Default: 2000 lines after start_line.", "minimum": 1},
			},
			"required": ["path"],
		},
		_view_script,
		true
	)
	registry.add_tool(
		"create_script",
		"Create a new GDScript file. Without 'content' a minimal template extending base_class is written. Fails if the file exists unless overwrite is true. Not undoable with Ctrl+Z.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path ending in .gd, e.g. res://scripts/player.gd."},
				"content": {"type": "string", "description": "Full source of the script. Optional."},
				"base_class": {"type": "string", "description": "Class to extend when using the template. Default Node."},
				"overwrite": {"type": "boolean", "description": "Replace an existing file. Default false."},
			},
			"required": ["path"],
		},
		_create_script
	)
	registry.add_tool(
		"update_script",
		"Replace the entire contents of an existing GDScript file. For small changes prefer edit_script. Not undoable with Ctrl+Z.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path of an existing .gd file."},
				"content": {"type": "string", "description": "The new full source of the script."},
			},
			"required": ["path", "content"],
		},
		_update_script
	)
	registry.add_tool(
		"edit_script",
		"Replace an exact piece of text in a GDScript file. old_text must match exactly (including tabs) and must be unique unless replace_all is true. Use view_script first to copy the exact text. Not undoable with Ctrl+Z.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "res:// path of an existing .gd file."},
				"old_text": {"type": "string", "description": "Exact text to find."},
				"new_text": {"type": "string", "description": "Replacement text (may be empty to delete)."},
				"replace_all": {"type": "boolean", "description": "Replace every occurrence. Default false."},
			},
			"required": ["path", "old_text", "new_text"],
		},
		_edit_script
	)
	registry.add_tool(
		"attach_script",
		"Attach a script to a node in the scene being edited, or detach the current script by passing an empty script_path. Supports undo (Ctrl+Z).",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string", "description": "Node path relative to the scene root. Use \".\" for the root."},
				"script_path": {"type": "string", "description": "res:// path of the script. Empty string detaches the script."},
			},
			"required": ["node_path", "script_path"],
		},
		_attach_script
	)


func _list_scripts(arguments: Dictionary) -> Dictionary:
	var include_addons := bool(arguments.get("include_addons", false))
	var found := []
	_collect_scripts("res://", include_addons, found)
	found.sort()
	var truncated := found.size() > MAX_LIST_RESULTS
	if truncated:
		found = found.slice(0, MAX_LIST_RESULTS)
	return {"scripts": found, "count": found.size(), "truncated": truncated}


func _view_script(arguments: Dictionary) -> Dictionary:
	var path := _normalize(str(arguments.get("path", "")))
	var problem := _check_path(path, false)
	if not problem.is_empty():
		return {"error": problem}
	if not FileAccess.file_exists(path):
		return {"error": "File not found: %s. Use list_scripts to see what exists." % path}

	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var line_count := 0
	if not text.is_empty():
		line_count = lines.size() - (1 if text.ends_with("\n") else 0)

	var start_line := maxi(1, int(arguments.get("start_line", 1)))
	var end_line := mini(line_count, int(arguments.get("end_line", start_line + DEFAULT_VIEW_LINES - 1)))
	var content := ""
	if start_line <= end_line:
		content = "\n".join(lines.slice(start_line - 1, end_line))
	return {
		"path": path,
		"line_count": line_count,
		"start_line": start_line,
		"end_line": end_line,
		"truncated": end_line < line_count,
		"content": content,
	}


func _create_script(arguments: Dictionary) -> Dictionary:
	var path := _normalize(str(arguments.get("path", "")))
	var problem := _check_path(path, true)
	if not problem.is_empty():
		return {"error": problem}
	var existed := FileAccess.file_exists(path)
	if existed and not bool(arguments.get("overwrite", false)):
		return {"error": "%s already exists. Pass overwrite=true to replace it, or use update_script / edit_script." % path}

	var content := str(arguments.get("content", ""))
	if content.is_empty():
		var base_class := str(arguments.get("base_class", "Node"))
		if not ClassDB.class_exists(base_class):
			return {"error": "Unknown base class '%s'." % base_class}
		content = "extends %s\n\n\nfunc _ready() -> void:\n\tpass\n" % base_class

	var result := _write_script(path, content)
	if result.has("error"):
		return result
	result["created"] = not existed
	return result


func _update_script(arguments: Dictionary) -> Dictionary:
	var path := _normalize(str(arguments.get("path", "")))
	var problem := _check_path(path, true)
	if not problem.is_empty():
		return {"error": problem}
	if not FileAccess.file_exists(path):
		return {"error": "%s does not exist. Use create_script to make a new file." % path}
	if not arguments.has("content"):
		return {"error": "Missing 'content'."}
	return _write_script(path, str(arguments["content"]))


func _edit_script(arguments: Dictionary) -> Dictionary:
	var path := _normalize(str(arguments.get("path", "")))
	var problem := _check_path(path, true)
	if not problem.is_empty():
		return {"error": problem}
	if not FileAccess.file_exists(path):
		return {"error": "%s does not exist." % path}

	var old_text := str(arguments.get("old_text", ""))
	var new_text := str(arguments.get("new_text", ""))
	if old_text.is_empty():
		return {"error": "old_text must not be empty."}

	var text := FileAccess.get_file_as_string(path)
	var occurrences := text.count(old_text)
	if occurrences == 0:
		return {"error": "old_text was not found. It must match exactly, including tabs and line endings. Use view_script to copy the exact text."}
	if occurrences > 1 and not bool(arguments.get("replace_all", false)):
		return {"error": "old_text matches %d places. Include more surrounding text to make it unique, or pass replace_all=true." % occurrences}

	var result := _write_script(path, text.replace(old_text, new_text))
	if result.has("error"):
		return result
	result["replacements"] = occurrences
	return result


func _attach_script(arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is open in the editor."}
	var node_path := str(arguments.get("node_path", ""))
	var node := _find_node(root, node_path)
	if node == null:
		return {"error": "Node not found: '%s'. Use get_hierarchy to see valid paths." % node_path}

	var script_path := _normalize(str(arguments.get("script_path", "")))
	var new_script: Script = null
	if not script_path.is_empty():
		var problem := _check_path(script_path, false)
		if not problem.is_empty():
			return {"error": problem}
		if not FileAccess.file_exists(script_path):
			return {"error": "File not found: %s. Create it first with create_script." % script_path}
		var loaded := load(script_path)
		if not (loaded is Script):
			return {"error": "%s could not be loaded as a script. Check the Output panel for errors." % script_path}
		new_script = loaded as Script
		var base_type := String(new_script.get_instance_base_type())
		if not base_type.is_empty() and not ClassDB.is_parent_class(node.get_class(), base_type):
			return {"error": "The script extends %s, but node '%s' is a %s." % [base_type, node_path, node.get_class()]}

	var old_script = node.get_script()
	var undo := _plugin.get_undo_redo()
	undo.create_action("Attach script to %s (AI)" % node.name, UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(node, "set_script", new_script)
	undo.add_undo_method(node, "set_script", old_script)
	undo.commit_action()

	return {
		"path": str(root.get_path_to(node)),
		"script": script_path,
	}


## Writes the file, refreshes the editor's view of it and reports whether it
## compiles. Returns {"path", "bytes", "compiles"} or {"error"}.
func _write_script(path: String, text: String) -> Dictionary:
	var folder := path.get_base_dir()
	var is_new := not FileAccess.file_exists(path)
	var folder_existed := DirAccess.dir_exists_absolute(folder)
	if not folder_existed:
		var dir_err := DirAccess.make_dir_recursive_absolute(folder)
		if dir_err != OK:
			return {"error": "Could not create folder %s: %s" % [folder, error_string(dir_err)]}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "Could not open %s for writing: %s" % [path, error_string(FileAccess.get_open_error())]}
	file.store_string(text)
	file.close()

	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.update_file(path)
	if (is_new or not folder_existed) and not filesystem.is_scanning():
		filesystem.scan()

	# If the script is already loaded, refresh the live copy with the new source;
	# otherwise load it fresh from disk. reload() then compiles it and its result
	# tells us whether it is valid. (can_instantiate() is NOT usable for this: in
	# the editor it returns false for every script that is not marked @tool.)
	var log_mark := 0
	if _log != null:
		log_mark = _log.last_id()
	var was_cached := ResourceLoader.has_cached(path)
	var compiles := false
	var reload_error: int = ERR_FILE_NOT_FOUND
	var loaded := load(path)
	if loaded is GDScript:
		var gd_script := loaded as GDScript
		if was_cached:
			gd_script.source_code = text
		reload_error = gd_script.reload(true)
		compiles = reload_error == OK

	var result := {"path": path, "bytes": text.to_utf8_buffer().size(), "compiles": compiles}
	if not compiles:
		result["note"] = "The script did not compile (%s)." % error_string(reload_error)
		var problems := _errors_since(log_mark)
		if problems.is_empty():
			result["note"] += " Check the Output panel for the error."
		else:
			result["compile_errors"] = problems
	return result


## Error messages the editor logged since the given log id, as short strings.
func _errors_since(since_id: int) -> Array:
	var out := []
	if _log == null:
		return out
	for entry in _log.read(since_id, "error", 10):
		var text := str(entry["text"])
		if entry.has("file") and not str(entry["file"]).is_empty():
			text += " (%s:%d)" % [entry["file"], int(entry.get("line", 0))]
		out.append(text)
	return out


func _normalize(path: String) -> String:
	return path.strip_edges().simplify_path()


## Returns an error message, or "" when the path is acceptable.
func _check_path(path: String, for_write: bool) -> String:
	if not path.begins_with("res://"):
		return "Path must start with res:// (got '%s')." % path
	if not path.ends_with(".gd"):
		return "Path must end with .gd (got '%s')." % path
	if path.begins_with("res://.godot"):
		return "The .godot folder is off limits."
	if for_write and path.begins_with(PROTECTED_PREFIX):
		return "Scripts of the MCP plugin itself can't be modified through this tool."
	return ""


func _find_node(root: Node, node_path: String) -> Node:
	if node_path.is_empty() or node_path == ".":
		return root
	return root.get_node_or_null(NodePath(node_path))


func _collect_scripts(dir_path: String, include_addons: bool, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				if include_addons or full != "res://addons":
					_collect_scripts(full, include_addons, out)
			elif entry.ends_with(".gd"):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
