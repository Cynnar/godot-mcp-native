@tool
extends RefCounted
## Returned by a tool that cannot answer immediately (e.g. it must wait for the
## running game). The HTTP server keeps the client connection open until
## finish() is called or the deadline passes, then sends the result.

var done := false
var value: Variant = null

var _deadline_msec := 0
var _timeout_message := "Timed out"


func _init(timeout_msec: int = 5000, timeout_message: String = "Timed out") -> void:
	_deadline_msec = Time.get_ticks_msec() + timeout_msec
	_timeout_message = timeout_message


func finish(result: Variant) -> void:
	if done:
		return
	value = result
	done = true


## True when the result is available or the deadline has passed.
func is_ready() -> bool:
	if not done and Time.get_ticks_msec() > _deadline_msec:
		finish({"error": _timeout_message})
	return done


func get_value() -> Variant:
	return value
