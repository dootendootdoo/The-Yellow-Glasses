class_name SpritePicker
extends Node
## Lets the player click and hover Sprite3D and AnimatedSprite3D nodes, counting
## only their opaque pixels.
##
## Add one to the scene. Sprites in the [constant GROUP] group are candidates, and
## [PickableAnimatedSprite3D] joins it by itself. Every frame the sprite under the
## cursor is found and told hover_enter() or hover_exit(); on a tap the sprite
## under it is told click(). Any node in the group with those methods works, so
## other pickable classes can be added later.
##
## No physics is involved: each candidate's quad is intersected with the camera
## ray, the hit is mapped back to a texel, and that texel's alpha is compared with
## [member alpha_threshold]. The nearest opaque hit wins. The GUI gets first
## refusal: taps are taken in _unhandled_input, and hover pauses while a Control
## is under the cursor.
##
## Not handled: billboarded sprites (skipped with a warning), and draw-order
## overrides such as [member GeometryInstance3D.render_priority] or
## [member GeometryInstance3D.sorting_offset], which are ignored in favour of
## plain distance along the ray.


## Group a sprite joins to be picked.
const GROUP := &"pickable"


## One sprite the ray met at an opaque texel.
class Hit extends RefCounted:
	## The sprite that was hit.
	var sprite: SpriteBase3D
	## The texel that was hit, in the current frame's own pixels, top-left origin.
	var pixel: Vector2i
	## Where the ray met the sprite's plane, in world space.
	var world_position: Vector3
	## Distance along the ray from its origin to [member world_position].
	var distance: float


## While false nothing is clicked or hovered, and a hovered sprite gets hover_exit().
@export var enabled: bool = true: set = set_enabled
## Camera the screen point is seen through. Leave empty for the viewport's current camera.
@export var camera: Camera3D
## A texel with alpha at or below this is a hole. 0.1 matches [method Sprite2D.is_pixel_opaque].
@export_range(0.0, 1.0, 0.01) var alpha_threshold: float = 0.1: set = set_alpha_threshold

var _hovered: SpriteBase3D
var _mouse_position: Vector2
var _mouse_inside: bool = false
# Texture2D -> BitMap of its opaque texels (or null if unreadable). Reading a
# texture back from the GPU is slow, so each one is read once. Only the one bit
# per texel is kept: the full images of a painting's worth of frames run to
# gigabytes, more than a web build can hold. See clear_cache().
var _masks: Dictionary = {}
# Instance ids of sprites already warned about, so the log is not spammed every frame.
var _warned: Dictionary = {}


func _ready() -> void:
	get_window().mouse_exited.connect(_on_window_mouse_exited)


func _input(event: InputEvent) -> void:
	# Only watching where the mouse is. Nothing is consumed here: the GUI has
	# not seen this event yet.
	if event is InputEventMouseMotion:
		_mouse_position = (event as InputEventMouseMotion).position
		_mouse_inside = true


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	# Every finger counts on touch. A touch also arrives as an emulated click,
	# which must not count a second time.
	var position: Vector2
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return
		position = touch.position
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT \
				or button.device == InputEvent.DEVICE_ID_EMULATION:
			return
		position = button.position
	else:
		return

	var hit := pick(position)
	if hit == null:
		return
	if hit.sprite.has_method(&"click"):
		hit.sprite.click()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not enabled:
		return
	# Polled rather than driven by mouse motion so a sprite animating under a
	# still cursor still enters and leaves hover.
	var sprite: SpriteBase3D = null
	if _mouse_inside and get_viewport().gui_get_hovered_control() == null:
		var hit := pick(_mouse_position)
		if hit != null:
			sprite = hit.sprite
	_set_hovered(sprite)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_set_hovered(null)


func set_alpha_threshold(value: float) -> void:
	if value == alpha_threshold:
		return
	alpha_threshold = value
	# The cached masks were cut at the old threshold.
	clear_cache()


## The nearest opaque sprite under [param screen_position], or null if there is none.
func pick(screen_position: Vector2) -> Hit:
	var hits := pick_all(screen_position)
	if hits.is_empty():
		return null
	return hits[0]


## Every opaque sprite under [param screen_position], nearest first.
func pick_all(screen_position: Vector2) -> Array[Hit]:
	var hits: Array[Hit] = []
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	if cam == null:
		return hits
	var origin := cam.project_ray_origin(screen_position)
	var direction := cam.project_ray_normal(screen_position)
	for node in get_tree().get_nodes_in_group(GROUP):
		var sprite := node as SpriteBase3D
		if sprite == null or not sprite.is_visible_in_tree():
			continue
		var hit := _test(sprite, origin, direction)
		if hit != null:
			hits.append(hit)
	hits.sort_custom(func(a: Hit, b: Hit) -> bool: return a.distance < b.distance)
	return hits


## Forget cached texture reads. Call this after changing an ImageTexture's
## contents at runtime, otherwise the picker keeps testing the old pixels.
func clear_cache() -> void:
	_masks.clear()


func _set_hovered(sprite: SpriteBase3D) -> void:
	if not is_instance_valid(_hovered):
		_hovered = null
	if sprite == _hovered:
		return
	if _hovered != null and _hovered.has_method(&"hover_exit"):
		_hovered.hover_exit()
	_hovered = sprite
	if _hovered != null and _hovered.has_method(&"hover_enter"):
		_hovered.hover_enter()


func _on_window_mouse_exited() -> void:
	_mouse_inside = false


func _test(sprite: SpriteBase3D, origin: Vector3, direction: Vector3) -> Hit:
	if sprite.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		_warn_once(sprite, "billboarded sprites are not pickable")
		return null
	var texture := _frame_texture(sprite)
	if texture == null:
		return null

	# Into the sprite's local space. affine_inverse copes with scaled ancestors.
	var to_local := sprite.global_transform.affine_inverse()
	var local_origin := to_local * origin
	var local_direction := to_local.basis * direction

	# The quad lies on the plane through the origin perpendicular to `axis`.
	var axis := sprite.axis
	if is_zero_approx(local_direction[axis]):
		return null # Edge on.
	var t := -local_origin[axis] / local_direction[axis]
	if t < 0.0:
		return null # Behind the camera.
	var local_point := local_origin + local_direction * t

	# Back to the 2D frame SpriteBase3D lays the quad out in (x right, y up,
	# pixel_size units). The axis cases mirror SpriteBase3D::draw_texture_rect.
	var quad_point: Vector2
	match axis:
		Vector3.AXIS_Z:
			quad_point = Vector2(local_point.x, local_point.y)
		Vector3.AXIS_Y:
			quad_point = Vector2(local_point.x, -local_point.z)
		Vector3.AXIS_X:
			quad_point = Vector2(-local_point.z, local_point.y)
	quad_point /= sprite.pixel_size

	var source := _frame_source(sprite, texture)
	var rect := _frame_rect(sprite, source.size)
	if rect.size.x < 1.0 or rect.size.y < 1.0 or not rect.has_point(quad_point):
		return null

	# Texel within the frame. Image rows run top to bottom, quad y runs bottom to top.
	var column := quad_point.x - rect.position.x
	var row := rect.end.y - quad_point.y
	if sprite.flip_h:
		column = rect.size.x - column
	if sprite.flip_v:
		row = rect.size.y - row
	var pixel := Vector2i(
		clampi(floori(column), 0, int(rect.size.x) - 1),
		clampi(floori(row), 0, int(rect.size.y) - 1),
	)

	if not _opaque_at(texture, Vector2i(source.position) + pixel):
		return null

	var hit := Hit.new()
	hit.sprite = sprite
	hit.pixel = pixel
	hit.world_position = sprite.global_transform * local_point
	hit.distance = (hit.world_position - origin).dot(direction)
	return hit


# The texture the sprite's current frame is drawn from, or null.
func _frame_texture(sprite: SpriteBase3D) -> Texture2D:
	if sprite is Sprite3D:
		return (sprite as Sprite3D).texture
	if sprite is AnimatedSprite3D:
		var animated := sprite as AnimatedSprite3D
		var frames := animated.sprite_frames
		if frames == null or not frames.has_animation(animated.animation):
			return null
		if animated.frame < 0 or animated.frame >= frames.get_frame_count(animated.animation):
			return null
		return frames.get_frame_texture(animated.animation, animated.frame)
	return null


# Where the current frame sits inside `texture`, in that texture's pixels.
# Mirrors Sprite3D::_draw (region and hframes/vframes) and AnimatedSprite3D::_draw.
func _frame_source(sprite: SpriteBase3D, texture: Texture2D) -> Rect2:
	if sprite is Sprite3D:
		var s := sprite as Sprite3D
		var base := s.region_rect if s.region_enabled else Rect2(Vector2.ZERO, texture.get_size())
		var frame_size := base.size / Vector2(s.hframes, s.vframes)
		@warning_ignore("integer_division")
		var cell := Vector2(s.frame % s.hframes, s.frame / s.hframes)
		return Rect2(base.position + cell * frame_size, frame_size)
	return Rect2(Vector2.ZERO, texture.get_size())


# The rectangle the frame is drawn into, in pixels before pixel_size, in the
# quad's 2D frame. Computed here rather than via get_item_rect(), which reports
# the wrong size for a region combined with hframes/vframes.
func _frame_rect(sprite: SpriteBase3D, frame_size: Vector2) -> Rect2:
	var position := sprite.offset
	if sprite.centered:
		position -= frame_size / 2.0
	return Rect2(position, frame_size)


# Whether one texel of `texture`, top-left origin, is opaque. Outside the texture is not.
func _opaque_at(texture: Texture2D, texel: Vector2i) -> bool:
	# An AtlasTexture is a window onto a bigger image; look through it.
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		if atlas.atlas == null:
			return false
		var in_region := texel - Vector2i(atlas.margin.position)
		if not Rect2i(Vector2i.ZERO, Vector2i(atlas.region.size)).has_point(in_region):
			return false # In the margin, which draws nothing.
		return _opaque_at(atlas.atlas, Vector2i(atlas.region.position) + in_region)
	var mask := _mask_for(texture)
	if mask == null or not Rect2i(Vector2i.ZERO, mask.get_size()).has_point(texel):
		return false
	return mask.get_bit(texel.x, texel.y)


func _mask_for(texture: Texture2D) -> BitMap:
	if _masks.has(texture):
		return _masks[texture]
	var image := texture.get_image()
	# VRAM-compressed imports (what the 3D detector picks) cannot be read per
	# texel until unpacked. Lossless imports come back ready to read.
	if image != null and image.is_compressed() and image.decompress() != OK:
		image = null
	var mask: BitMap = null
	if image == null or image.is_empty():
		push_warning("SpritePicker: cannot read pixels of %s" % texture.resource_path)
	else:
		mask = BitMap.new()
		mask.create_from_image_alpha(image, alpha_threshold)
	_masks[texture] = mask
	return mask


func _warn_once(sprite: SpriteBase3D, reason: String) -> void:
	var id := sprite.get_instance_id()
	if _warned.has(id):
		return
	_warned[id] = true
	push_warning("SpritePicker: skipping %s, %s" % [sprite.get_path(), reason])
