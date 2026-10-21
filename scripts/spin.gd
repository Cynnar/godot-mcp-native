extends Sprite2D

## Rotation speed in degrees per second.
@export var degrees_per_second: float = 90.0


func _process(delta: float) -> void:
	rotation += deg_to_rad(degrees_per_second) * delta
