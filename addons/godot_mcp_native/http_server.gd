@tool
extends RefCounted
## Minimal HTTP/1.1 server used by the plugin. Binds to 127.0.0.1 only.
##
## Requests are parsed and handled on the main thread from poll(), because the
## editor API may only be used from the main thread. Each connection serves one
## request and is then closed ("Connection: close"), which keeps this simple.

const MAX_HEADER_BYTES := 16 * 1024
const MAX_BODY_BYTES := 8 * 1024 * 1024
const CLIENT_TIMEOUT_MSEC := 15000

class _Client extends RefCounted:
	var peer: StreamPeerTCP
	var buffer := PackedByteArray()
	var since_msec := 0

## Port the server is listening on, or 0 when stopped.
var port := 0

var _server := TCPServer.new()
var _clients: Array = []
var _handler: Callable


## Starts listening on the first free port in [preferred_port, preferred_port + attempts).
## handler signature: func(method: String, target: String, headers: Dictionary, body: String) -> Dictionary
## handler returns {"status": int, "headers": Dictionary (optional), "body": String}.
func start(preferred_port: int, handler: Callable, attempts: int = 10) -> Error:
	_handler = handler
	for i in attempts:
		var candidate := preferred_port + i
		if _server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			return OK
	return ERR_CANT_CREATE


func stop() -> void:
	for c in _clients:
		c.peer.disconnect_from_host()
	_clients.clear()
	if _server.is_listening():
		_server.stop()
	port = 0


func is_running() -> bool:
	return _server.is_listening()


## Call every frame.
func poll() -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var c := _Client.new()
		c.peer = _server.take_connection()
		c.since_msec = Time.get_ticks_msec()
		_clients.append(c)
	for i in range(_clients.size() - 1, -1, -1):
		if _service(_clients[i]):
			_clients.remove_at(i)


## Returns true when the client is finished (answered, failed or timed out).
func _service(c: _Client) -> bool:
	var peer := c.peer
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return true
	if Time.get_ticks_msec() - c.since_msec > CLIENT_TIMEOUT_MSEC:
		_respond(peer, {"status": 408, "body": ""})
		return true

	var available := peer.get_available_bytes()
	if available > 0:
		var chunk := peer.get_data(available)
		if chunk[0] != OK:
			return true
		c.buffer.append_array(chunk[1])

	var header_end := _find_header_end(c.buffer)
	if header_end < 0:
		if c.buffer.size() > MAX_HEADER_BYTES:
			_respond(peer, {"status": 431, "body": ""})
			return true
		return false

	var head := c.buffer.slice(0, header_end).get_string_from_utf8().split("\r\n")
	var request_line := head[0].split(" ")
	if request_line.size() < 2:
		_respond(peer, {"status": 400, "body": ""})
		return true

	var headers := {}
	for i in range(1, head.size()):
		var colon := head[i].find(":")
		if colon > 0:
			headers[head[i].substr(0, colon).strip_edges().to_lower()] = head[i].substr(colon + 1).strip_edges()

	var content_length := int(headers.get("content-length", "0"))
	if content_length < 0 or content_length > MAX_BODY_BYTES:
		_respond(peer, {"status": 413, "body": ""})
		return true

	var body_start := header_end + 4
	if c.buffer.size() - body_start < content_length:
		return false  # body still arriving

	var body := c.buffer.slice(body_start, body_start + content_length).get_string_from_utf8()
	var response: Dictionary = _handler.call(request_line[0], request_line[1], headers, body)
	_respond(peer, response)
	return true


func _find_header_end(buf: PackedByteArray) -> int:
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


func _respond(peer: StreamPeerTCP, response: Dictionary) -> void:
	var code: int = response.get("status", 200)
	var body_bytes := String(response.get("body", "")).to_utf8_buffer()
	var lines := PackedStringArray(["HTTP/1.1 %d %s" % [code, _reason(code)]])
	var extra: Dictionary = response.get("headers", {})
	for key in extra:
		lines.append("%s: %s" % [key, extra[key]])
	lines.append("Content-Length: %d" % body_bytes.size())
	lines.append("Connection: close")
	lines.append("")
	lines.append("")
	peer.put_data("\r\n".join(lines).to_utf8_buffer() + body_bytes)
	peer.disconnect_from_host()


func _reason(code: int) -> String:
	match code:
		200: return "OK"
		202: return "Accepted"
		204: return "No Content"
		400: return "Bad Request"
		403: return "Forbidden"
		404: return "Not Found"
		405: return "Method Not Allowed"
		408: return "Request Timeout"
		413: return "Payload Too Large"
		431: return "Request Header Fields Too Large"
		_: return "Status"
