@tool
extends EditorPlugin
## Entry point. Starts the built-in MCP server when the plugin is enabled and
## shows a status dock in the bottom panel.

const McpHttpServer := preload("res://addons/godot_mcp_native/http_server.gd")
const McpProtocol := preload("res://addons/godot_mcp_native/mcp_protocol.gd")
const ToolRegistry := preload("res://addons/godot_mcp_native/tool_registry.gd")
const CoreTools := preload("res://addons/godot_mcp_native/tools/core_tools.gd")
const EditorTools := preload("res://addons/godot_mcp_native/tools/editor_tools.gd")
const EditorWriteTools := preload("res://addons/godot_mcp_native/tools/editor_write_tools.gd")
const McpDock := preload("res://addons/godot_mcp_native/ui/mcp_dock.gd")

const PREFERRED_PORT := 6550

var _http: McpHttpServer
var _protocol: McpProtocol
var _registry: ToolRegistry
var _tool_modules: Array = []  # kept alive: Callables do not hold RefCounted objects
var _dock: McpDock


func _enter_tree() -> void:
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

	_protocol = McpProtocol.new(_registry)
	_http = McpHttpServer.new()
	var err := _http.start(PREFERRED_PORT, _protocol.handle_http)

	_dock = McpDock.new()
	add_control_to_bottom_panel(_dock, "MCP")

	if err == OK:
		_dock.set_port(_http.port)
		print("[Godot MCP Native] listening on http://127.0.0.1:%d/mcp" % _http.port)
	else:
		_dock.set_port(0)
		push_error("[Godot MCP Native] could not open a local port starting at %d" % PREFERRED_PORT)
	set_process(true)


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
	_http = null
	_protocol = null
	_registry = null
	_tool_modules.clear()
