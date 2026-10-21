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


func _init() -> void:
	name = "MCP"
	var title := Label.new()
	title.text = "Godot MCP Native"
	add_child(title)
	add_child(_status_label)
	add_child(_url_label)
	_add_copy_button("Copy Claude Code command", _claude_code_command)
	_add_copy_button("Copy Claude Desktop config", _claude_desktop_config)
	set_port(0)


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
