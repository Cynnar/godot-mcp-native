@tool
extends Logger
## Collects engine log output (print, push_error, push_warning, script and
## shader errors) from the editor process into a bounded buffer for the tools.
##
## Godot may call the virtual methods below from ANY thread, possibly at the
## same time, so everything that touches the buffer is guarded by a mutex.
## Never print() or push_error() from inside these methods: that would recurse.

const MAX_ENTRIES := 1000
const MAX_TEXT_CHARS := 4000

# Logger.ErrorType values (kept as plain numbers so this file does not depend
# on how the enum is exposed to subclasses).
const ERRTYPE_WARNING := 1
const ERRTYPE_SCRIPT := 2
const ERRTYPE_SHADER := 3

var _mutex := Mutex.new()
var _entries: Array = []
var _last_id := 0


func _log_message(message: String, error: bool) -> void:
	_add({"level": "error" if error else "info", "text": message.rstrip("\r\n")})


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var entry := {
		"level": "warning" if error_type == ERRTYPE_WARNING else "error",
		"text": rationale if not rationale.is_empty() else code,
		"file": file,
		"line": line,
		"function": function,
	}
	if error_type == ERRTYPE_SCRIPT:
		entry["kind"] = "script"
	elif error_type == ERRTYPE_SHADER:
		entry["kind"] = "shader"
	_add(entry)


## Id of the most recent entry (0 when nothing has been logged yet).
func last_id() -> int:
	_mutex.lock()
	var id := _last_id
	_mutex.unlock()
	return id


## Returns copies of the entries newer than since_id, at most max_entries of the
## most recent ones. level_filter is "all", "error", "warning" or "info".
func read(since_id: int = 0, level_filter: String = "all", max_entries: int = 100) -> Array:
	var out := []
	_mutex.lock()
	for entry in _entries:
		if entry["id"] <= since_id:
			continue
		if level_filter != "all" and entry["level"] != level_filter:
			continue
		out.append(entry.duplicate())
	_mutex.unlock()
	if out.size() > max_entries:
		out = out.slice(out.size() - max_entries)
	return out


func clear() -> void:
	_mutex.lock()
	_entries.clear()
	_mutex.unlock()


func _add(entry: Dictionary) -> void:
	entry["text"] = String(entry["text"]).left(MAX_TEXT_CHARS)
	_mutex.lock()
	_last_id += 1
	entry["id"] = _last_id
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)
	_mutex.unlock()
