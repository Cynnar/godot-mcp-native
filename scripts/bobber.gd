extends Sprite2D

## How far the sprite moves above and below its start position, in pixels.
@export var bob_height: float = 25.0
## Bob cycles per second, in radians of the sine wave per second.
@export var bob_speed: float = 2.0

var _base_y: float
var _time: float = 0.0


func _ready() -> void:
	_base_y = position.y


func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height
