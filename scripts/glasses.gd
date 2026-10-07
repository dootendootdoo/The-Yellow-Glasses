extends Sprite3D
## First click: the camera moves forward, and the background moves with it.
## Second click: the camera moves on through the background (which stays put
## or fades), and the next scene loads.

enum Stage { IDLE, MOVING, MOVED, LEAVING }

## Leave empty to use the current camera (it must use parallax_camera.gd).
@export var camera: ParallaxCamera
## The background that stays glued to the camera on the first click.
@export var background: Node3D

@export_group("First Click")
## How far the camera moves on the first click, relative to where it faces.
## X = sideways (negative is left), Y = up/down, Z = forward/back (negative is forward).
@export var first_offset: Vector3 = Vector3(-1, 1.0, -6.0)
@export var first_duration: float = 1.0

@export_group("Second Click")
## Make this far enough to pass the background.
@export var second_distance: float = 10.0
@export var second_duration: float = 1.0 
## On: the background fades out. Off: the camera flies through it.
@export var hide_background: bool = false
@export_file("*.tscn") var next_scene: String
## Optional full-screen black ColorRect that fades in at the end.
@export var fade_rect: ColorRect
## How far past the background the camera goes.
@export var pass_margin: float = 2.0

@export_group("Color Swap")
## The three items that turn gray once the glasses unlock.
## Leave empty to find them by unique name (%Hat, %Beard, %Forehead).
@export var hat: Node3D
@export var beard: Node3D
@export var forehead: Node3D
@export var color_fade_duration: float = 1.0

var _stage := Stage.IDLE
var _colored := false

func _init() -> void:
	add_to_group(SpritePicker.GROUP)


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d() as ParallaxCamera
	if camera == null:
		push_error("Glasses: the camera needs the ParallaxCamera script.")
	if background == null:
		background = get_node_or_null("%Background_scrolling") as Node3D
	if fade_rect != null:
		fade_rect.modulate.a = 0.0

	if hat == null:
		hat = get_node_or_null("%Hat") as Node3D
	if beard == null:
		beard = get_node_or_null("%Beard") as Node3D
	if forehead == null:
		forehead = get_node_or_null("%Forehead") as Node3D

	# Start in grayscale.
	var control = _saturation_of(self)
	if control != null:
		control.saturation = 0.0

	GameState.progress_changed.connect(_on_progress_changed)
	# Covers the testing shortcut where all flags start true.
	_on_progress_changed()


# When the third item is clicked: glasses to color, the items to gray. Runs once.
func _on_progress_changed() -> void:
	if _colored or not GameState.glasses_unlocked():
		return
	_colored = true
	_fade(self, 1.0)
	for item in [hat, beard, forehead]:
		_fade(item, 0.0)


func _fade(node: Node3D, target: float) -> void:
	var control = _saturation_of(node)
	if control == null:
		return
	control.fade_to(target, color_fade_duration)


# The SaturationControl child of `node`, or null with a warning.
func _saturation_of(node: Node3D) -> Node:
	if node == null:
		push_warning("Glasses: an item for the color swap is not assigned.")
		return null
	var control := node.get_node_or_null("SaturationControl")
	if control == null:
		push_warning("Glasses: %s has no SaturationControl child." % node.name)
	return control



## Called by the SpritePicker.
func click() -> void:
	if not GameState.glasses_unlocked():
		return
	match _stage:
		Stage.IDLE:
			_first_move()
		Stage.MOVED:
			_second_move()
		# Clicks during a move are ignored.


func _first_move() -> void:
	_stage = Stage.MOVING
	var tween := create_tween().set_parallel() \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "travel", camera.travel + first_offset, first_duration)
	# A background parented to the camera already follows it.
	if background != null and not camera.is_ancestor_of(background):
		# Same movement, same timing, so it stays glued to the camera.
		tween.tween_property(background, "global_position",
				background.global_position + _world_offset(first_offset), first_duration)
	await tween.finished
	_stage = Stage.MOVED



func _second_move() -> void:
	_stage = Stage.LEAVING
	var distance := second_distance

	if background != null:
		# Detach from the camera so the camera can fly through it.
		if camera.is_ancestor_of(background):
			background.reparent(camera.get_parent(), true)
		# Travel far enough to pass the background.
		distance = maxf(second_distance, _distance_to(background) + pass_margin)
		print("Glasses: background is ", _distance_to(background), " ahead, travelling ", distance)

	var tween := create_tween().set_parallel()
	tween.tween_property(camera, "travel",
			camera.travel + Vector3(0, 0, -distance), second_duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if background != null and hide_background:
		tween.tween_property(background, "modulate:a", 0.0, second_duration * 0.5)
	if fade_rect != null:
		tween.tween_property(fade_rect, "modulate:a", 1.0, second_duration * 0.5) \
				.set_delay(second_duration * 0.5)
	await tween.finished

	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)


# How far `node` is in front of the camera, along its facing direction.
func _distance_to(node: Node3D) -> float:
	var forward := -camera.global_transform.basis.z
	return (node.global_position - camera.global_position).dot(forward)



# The camera's forward travel of `distance`, converted to world space.
func _world_offset(local: Vector3) -> Vector3:
	var parent := camera.get_parent_node_3d()
	return parent.global_transform.basis * local if parent != null else local
