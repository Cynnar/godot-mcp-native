@tool
extends EditorPlugin
## Entry point. Starts the built-in MCP server when the plugin is enabled and
## shows a status dock in the bottom panel.

const McpHttpServer := preload("res://addons/godot_mcp_native/http_server.gd")
const McpProtocol := preload("res://addons/godot_mcp_native/mcp_protocol.gd")
const ToolRegistry := preload("res://addons/godot_mcp_native/tool_registry.gd")
const LogCapture := preload("res://addons/godot_mcp_native/log_capture.gd")
const CoreTools := preload("res://addons/godot_mcp_native/tools/core_tools.gd")
const EditorTools := preload("res://addons/godot_mcp_native/tools/editor_tools.gd")
const EditorWriteTools := preload("res://addons/godot_mcp_native/tools/editor_write_tools.gd")
const SceneTools := preload("res://addons/godot_mcp_native/tools/scene_tools.gd")
const ProjectTools := preload("res://addons/godot_mcp_native/tools/project_tools.gd")
const ResourceTools := preload("res://addons/godot_mcp_native/tools/resource_tools.gd")
const ScriptTools := preload("res://addons/godot_mcp_native/tools/script_tools.gd")
const RunTools := preload("res://addons/godot_mcp_native/tools/run_tools.gd")
const GameBridge := preload("res://addons/godot_mcp_native/game_bridge.gd")
const GameTools := preload("res://addons/godot_mcp_native/tools/game_tools.gd")
const McpDock := preload("res://addons/godot_mcp_native/ui/mcp_dock.gd")

const PREFERRED_PORT := 6550
const READ_ONLY_SETTING := "godot_mcp_native/read_only_mode"
const AUTOLOAD_NAME := "GodotMcpNativeBridge"
const AUTOLOAD_PATH := "res://addons/godot_mcp_native/runtime/mcp_runtime_bridge.gd"

var _http: McpHttpServer
var _protocol: McpProtocol
var _registry: ToolRegistry
var _log_capture: LogCapture
var _tool_modules: Array = []  # kept alive: Callables do not hold RefCounted objects
var _dock: McpDock
var _game_bridge: GameBridge


func _enter_tree() -> void:
	_log_capture = LogCapture.new()
	OS.add_logger(_log_capture)

	# The runtime bridge lives in the game process as an autoload. Ensure it on
	# every load (the plugin may already have been enabled in project.godot).
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_game_bridge = GameBridge.new(_log_capture)
	add_debugger_plugin(_game_bridge)

	_registry = ToolRegistry.new()
	var core := CoreTools.new()
	core.register(_registry)
	_tool_modules.append(core)
	var editor_tools := EditorTools.new()
	editor_tools.register(_registry)
	_tool_modules.append(editor_tools)
	var write_tools := EditorWriteTools.new()
	write_tools.register(_registry, self)
	_tool_modules.append(write_tools)
	var scene_tools := SceneTools.new()
	scene_tools.register(_registry, self)
	_tool_modules.append(scene_tools)
	var project_tools := ProjectTools.new()
	project_tools.register(_registry)
	_tool_modules.append(project_tools)
	var resource_tools := ResourceTools.new()
	resource_tools.register(_registry)
	_tool_modules.append(resource_tools)
	var script_tools := ScriptTools.new()
	script_tools.register(_registry, self, _log_capture)
	_tool_modules.append(script_tools)
	var run_tools := RunTools.new()
	run_tools.register(_registry, _log_capture)
	_tool_modules.append(run_tools)

	var game_tools := GameTools.new()
	game_tools.register(_registry, _game_bridge)
	_tool_modules.append(game_tools)

	_protocol = McpProtocol.new(_registry)
	_http = McpHttpServer.new()
	var err := _http.start(PREFERRED_PORT, _protocol.handle_http)

	_dock = McpDock.new()
	var editor_settings := EditorInterface.get_editor_settings()
	_registry.read_only_mode = bool(editor_settings.get_setting(READ_ONLY_SETTING)) if editor_settings.has_setting(READ_ONLY_SETTING) else false
	_dock.set_read_only(_registry.read_only_mode)
	_dock.read_only_toggled.connect(_on_read_only_toggled)
	add_control_to_bottom_panel(_dock, "MCP")

	if err == OK:
		_dock.set_port(_http.port)
		print("[Godot MCP Native] listening on http://127.0.0.1:%d/mcp" % _http.port)
	else:
		_dock.set_port(0)
		push_error("[Godot MCP Native] could not open a local port starting at %d" % PREFERRED_PORT)
	set_process(true)


func _on_read_only_toggled(enabled: bool) -> void:
	if _registry:
		_registry.read_only_mode = enabled
	# Stored in editor settings (per user), not in the project, so it is never committed.
	EditorInterface.get_editor_settings().set_setting(READ_ONLY_SETTING, enabled)
	print("[Godot MCP Native] read-only mode %s" % ("ON" if enabled else "off"))


func _process(_delta: float) -> void:
	if _http:
		_http.poll()


func _exit_tree() -> void:
	set_process(false)
	if _http:
		_http.stop()
	if _dock:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
	if _game_bridge:
		remove_debugger_plugin(_game_bridge)
	if _log_capture:
		OS.remove_logger(_log_capture)
	_http = null
	_protocol = null
	_registry = null
	_log_capture = null
	_game_bridge = null
	_tool_modules.clear()


## Called when the user turns the plugin off: take the autoload out of project.godot.
func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
