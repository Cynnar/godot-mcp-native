extends Node
## Runs INSIDE the game (added as an autoload by the plugin). Talks to the editor
## through Godot's built-in debugger channel; does nothing when the game is not
## launched from the editor, so it is harmless in exported builds.
##
## Deliberately not a @tool script: it must never run in the editor itself.

const PREFIX := "godot_mcp_native"
const MAX_LOG_PER_FRAME := 50
const MAX_LOG_BACKLOG := 2000
const DEFAULT_MAX_WIDTH := 1024

const ERRTYPE_WARNING := 1
const ERRTYPE_SCRIPT := 2
const ERRTYPE_SHADER := 3


## Collects the game's log output. Callbacks may arrive on any thread, so the
## buffer is mutex-guarded. Never print or push_error in here (recursion).
class GameLogger extends Logger:
	var mutex := Mutex.new()
	var pending: Array = []

	func _log_message(message: String, error: bool) -> void:
		_push({"level": "error" if error else "info", "text": message.rstrip("\r\n")})

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var entry := {
			"level": "warning" if error_type == 1 else "error",
			"text": rationale if not rationale.is_empty() else code,
			"file": file,
			"line": line,
			"function": function,
		}
		if error_type == 2:
			entry["kind"] = "script"
		elif error_type == 3:
			entry["kind"] = "shader"
		_push(entry)

	func _push(entry: Dictionary) -> void:
		mutex.lock()
		pending.append(entry)
		if pending.size() > 2000:
			pending.remove_at(0)
		mutex.unlock()

	func take(max_count: int) -> Array:
		mutex.lock()
		var out := pending.slice(0, max_count)
		pending = pending.slice(out.size())
		mutex.unlock()
		return out


var _logger: GameLogger


func _ready() -> void:
	if not EngineDebugger.is_active():
		set_process(false)
		return
	EngineDebugger.register_message_capture(PREFIX, _on_message)
	_logger = GameLogger.new()
	OS.add_logger(_logger)
	set_process(true)


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null
	if EngineDebugger.is_active() and EngineDebugger.has_capture(PREFIX):
		EngineDebugger.unregister_message_capture(PREFIX)


func _process(_delta: float) -> void:
	if _logger == null:
		return
	var batch := _logger.take(MAX_LOG_PER_FRAME)
	if not batch.is_empty():
		EngineDebugger.send_message(PREFIX + ":log", batch)


## message has the "godot_mcp_native:" prefix stripped. Return true when handled.
func _on_message(message: String, data: Array) -> bool:
	if message == "screenshot":
		_screenshot(data)
		return true
	return false


func _screenshot(data: Array) -> void:
	var request_id := int(data[0]) if data.size() > 0 else 0
	var max_width := int(data[1]) if data.size() > 1 else DEFAULT_MAX_WIDTH
	var image: Image = null
	var viewport := get_viewport()
	if viewport != null and viewport.get_texture() != null:
		image = viewport.get_texture().get_image()
	if image == null or image.is_empty():
		EngineDebugger.send_message(PREFIX + ":screenshot", [request_id, PackedByteArray(), 0, 0, "The game has no image to capture (running headless?)."])
		return
	var width := image.get_width()
	var height := image.get_height()
	if max_width > 0 and width > max_width:
		height = maxi(1, int(round(float(height) * float(max_width) / float(width))))
		width = max_width
		image.resize(width, height, Image.INTERPOLATE_BILINEAR)
	EngineDebugger.send_message(PREFIX + ":screenshot", [request_id, image.save_png_to_buffer(), width, height, ""])
