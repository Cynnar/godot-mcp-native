@tool
extends EditorDebuggerPlugin
## Editor side of the game bridge. Receives messages sent by the runtime
## autoload (runtime/mcp_runtime_bridge.gd) over the debugger channel and lets
## tools send requests to the running game.

const AsyncResult := preload("res://addons/godot_mcp_native/async_result.gd")
const PREFIX := "godot_mcp_native"
const SCREENSHOT_TIMEOUT_MSEC := 8000

var _log  # LogCapture
var _next_request := 1
var _waiting := {}  # request id -> AsyncResult


func _init(log_capture = null) -> void:
	_log = log_capture


func _has_capture(prefix: String) -> bool:
	return prefix == PREFIX


## message arrives WITH the prefix here, e.g. "godot_mcp_native:log".
func _capture(message: String, data: Array, _session_id: int) -> bool:
	var kind := message.get_slice(":", 1)
	if kind == "log":
		if _log != null:
			for entry in data:
				if typeof(entry) == TYPE_DICTIONARY:
					entry["source"] = "game"
					_log.add_entry(entry)
		return true
	if kind == "screenshot":
		_on_screenshot(data)
		return true
	return false


func has_active_session() -> bool:
	for session in get_sessions():
		if session.is_active():
			return true
	return false


## Asks the running game for a screenshot. Returns an AsyncResult that resolves
## to a tool result Dictionary (with "_image" on success).
func request_screenshot(max_width: int) -> AsyncResult:
	var result := AsyncResult.new(SCREENSHOT_TIMEOUT_MSEC, "The game did not answer. Is the bridge autoload (GodotMcpNativeBridge) present, and is the game paused at a breakpoint?")
	var target: EditorDebuggerSession = null
	for session in get_sessions():
		if session.is_active():
			target = session
			break
	if target == null:
		result.finish({"error": "No running game is connected to the editor. Use play_scene first and wait a moment for it to start."})
		return result
	var id := _next_request
	_next_request += 1
	_waiting[id] = result
	target.send_message(PREFIX + ":screenshot", [id, max_width])
	return result


func _on_screenshot(data: Array) -> void:
	if data.size() < 5:
		return
	var id := int(data[0])
	if not _waiting.has(id):
		return
	var result: AsyncResult = _waiting[id]
	_waiting.erase(id)
	var error_text := str(data[4])
	if not error_text.is_empty():
		result.finish({"error": error_text})
		return
	var png: PackedByteArray = data[1]
	result.finish({
		"width": int(data[2]),
		"height": int(data[3]),
		"bytes": png.size(),
		"_image": {"data": Marshalls.raw_to_base64(png), "mime": "image/png"},
	})
