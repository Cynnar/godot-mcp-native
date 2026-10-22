@tool
extends VBoxContainer
## Bottom-panel UI: server status plus one-click setup snippets for each client.

# Server name used in the generated client configs. Deliberately not plain
# "godot" so it does not collide with other Godot MCP servers people may have.
const CLIENT_SERVER_NAME := "godot-native"

var _status_label := Label.new()
var _url_label := Label.new()
var _buttons: Array[Button] = []
var _port := 0
var _read_only_check := CheckButton.new()
var _log_view := RichTextLabel.new()
var _registry = null
var _log_dirty := false

## Emitted when the user flips the read-only switch.
signal read_only_toggled(enabled: bool)


func _init() -> void:
	name = "MCP"
	var title := Label.new()
	title.text = "Godot MCP Native"
	add_child(title)
	add_child(_status_label)
	add_child(_url_label)
	_read_only_check.text = "Read-only mode (block all changes)"
	_read_only_check.tooltip_text = "When on, AI clients can read the project but every tool that changes it, runs the game or edits files is refused."
	_read_only_check.toggled.connect(func(on: bool): read_only_toggled.emit(on))
	add_child(_read_only_check)
	_add_copy_button("Copy Claude Code command", _claude_code_command)
	_add_copy_button("Copy Claude Desktop config", _claude_desktop_config)
	var log_title := Label.new()
	log_title.text = "Tool calls (newest at the bottom)"
	add_child(log_title)
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = true
	_log_view.selection_enabled = true
	_log_view.custom_minimum_size = Vector2(0, 140)
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_log_view)
	var clear_button := Button.new()
	clear_button.text = "Clear call log"
	clear_button.pressed.connect(_on_clear_pressed)
	add_child(clear_button)
	set_port(0)


## Connects the call log view to the tool registry.
func set_registry(registry) -> void:
	_registry = registry
	registry.call_log_changed.connect(func(): _log_dirty = true)
	_log_dirty = true
	set_process(true)


func _on_clear_pressed() -> void:
	if _registry != null:
		_registry.clear_call_log()


func _process(_delta: float) -> void:
	if _log_dirty:
		_log_dirty = false
		_refresh_log()


func _refresh_log() -> void:
	if _registry == null:
		return
	_log_view.clear()
	for entry in _registry.call_log:
		var color := "gray"
		var mark := "..."
		match str(entry["status"]):
			"ok":
				color = "green"
				mark = "ok %d ms" % int(entry["ms"])
			"error":
				color = "red"
				mark = "error %d ms" % int(entry["ms"])
			"blocked":
				color = "orange"
				mark = "BLOCKED (read-only)"
		var args_text := str(entry["args"]).replace("[", "[lb]")
		_log_view.append_text("[color=gray]%s[/color]  [b]%s[/b]  %s  [color=%s]%s[/color]\n" % [entry["time"], entry["tool"], args_text, color, mark])


## Sets the switch without emitting read_only_toggled.
func set_read_only(enabled: bool) -> void:
	_read_only_check.set_pressed_no_signal(enabled)


## Pass the listening port, or 0 when the server is not running.
func set_port(port: int) -> void:
	_port = port
	if port > 0:
		_status_label.text = "Status: running on 127.0.0.1:%d" % port
		_url_label.text = "Endpoint: %s" % _endpoint_url()
	else:
		_status_label.text = "Status: not running (no free port found)"
		_url_label.text = ""
	for button in _buttons:
		button.disabled = port <= 0


func _add_copy_button(label: String, builder: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func(): DisplayServer.clipboard_set(builder.call()))
	add_child(button)
	_buttons.append(button)


func _endpoint_url() -> String:
	return "http://127.0.0.1:%d/mcp" % _port


func _claude_code_command() -> String:
	return "claude mcp add --transport http %s %s" % [CLIENT_SERVER_NAME, _endpoint_url()]


# Claude Desktop launches stdio servers from its config file, so the HTTP
# endpoint is reached through the mcp-remote bridge (needs Node.js).
func _claude_desktop_config() -> String:
	var config := {
		"mcpServers": {
			CLIENT_SERVER_NAME: {
				"command": "npx",
				"args": ["-y", "mcp-remote", _endpoint_url()],
			}
		}
	}
	return JSON.stringify(config, "  ")
