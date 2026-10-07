class_name ParallaxCamera
extends Camera3D

# How far the camera can move from its starting spot (x = sideways, y = up/down).
@export var move_amount: Vector2 = Vector2(0.3, 0.2)

# The distance in front of the camera that it stays "focused" on.
# Things at this depth stay still. Set to 0 for no turning at all.
@export var focus_distance: float = 6.0

# How quickly the camera catches up to the mouse. Lower = floatier.
@export var smoothing: float = 4.0

## Offset from the starting spot, applied without smoothing.
## Tween this to move the camera. The mouse sway keeps working on top of it.
var travel: Vector3 = Vector3.ZERO

var start_position: Vector3
var _sway_position: Vector3


func _ready() -> void:
	start_position = position
	_sway_position = position


func _process(delta: float) -> void:
	# Where is the mouse? -1 to 1 on each axis, with 0 at the center of the screen.
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse := get_viewport().get_mouse_position()
	var offset := (mouse / viewport_size) * 2.0 - Vector2.ONE
	offset = offset.clamp(Vector2(-1, -1), Vector2(1, 1))

	# Where the sway wants to be.
	var target := start_position + Vector3(offset.x * move_amount.x, -offset.y * move_amount.y, 0.0)

	# Glide the sway smoothly, then add travel on top.
	var weight := 1.0 - exp(-smoothing * delta)
	_sway_position = _sway_position.lerp(target, weight)
	position = _sway_position + travel

	# Keep looking at the focus point, which travels with the camera.
	if focus_distance > 0.0:
		look_at(start_position + travel + Vector3(0, 0, -focus_distance))
