extends SpriteBase3D
## Moves this pupil toward the mouse cursor, within a small circle around
## where it was placed in the editor.

## How far the pupil can move from its rest spot, in texture pixels.
@export var max_offset_pixels: float = 6.0
## How far the cursor must be from the pupil, in texture pixels, for the
## pupil to reach max_offset_pixels. Closer than this, it moves less.
@export var reach_pixels: float = 300.0
## Higher values follow the mouse more quickly.
@export var follow_speed: float = 4.0

# Where the pupil sits in the editor, in the parent's space.
var _rest_position: Vector3


func _ready() -> void:
	_rest_position = position


func _process(delta: float) -> void:
	var target := _rest_position + _look_offset()
	position = position.lerp(target, 1.0 - exp(-follow_speed * delta))


# Offset from the rest position toward the cursor, in the parent's space.
func _look_offset() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var parent := get_parent_node_3d()
	if camera == null or parent == null:
		return Vector3.ZERO

	# Find where the mouse ray meets the plane the pupil lies on.
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var rest_global := parent.to_global(_rest_position)
	var plane := Plane(global_transform.basis.z, rest_global)
	var hit = plane.intersects_ray(origin, direction)
	if hit == null:
		return Vector3.ZERO

	var toward: Vector3 = parent.to_local(hit) - _rest_position
	if toward.length() < 0.0001:
		return Vector3.ZERO

	# Convert between texture pixels and parent units.
	var pixel_to_local := pixel_size * scale.x
	var distance_pixels := toward.length() / pixel_to_local
	var amount := clampf(distance_pixels / reach_pixels, 0.0, 1.0)
	return toward.normalized() * max_offset_pixels * pixel_to_local * amount
