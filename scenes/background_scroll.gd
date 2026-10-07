extends MeshInstance3D
## Scrolls the material's texture sideways. Once the hat, beard and forehead
## are all clicked, it changes to a new speed and direction.

## How fast the image moves, in "image widths per second".
## 0.02 = one full loop every 50 seconds.
@export var scroll_speed: float = -.02
## Speed after the puzzle is solved. Negative reverses the direction.
@export var solved_scroll_speed: float = 0.1
## Seconds to blend to the new speed. 0 switches instantly.
@export var speed_change_duration: float = 2.0

var _current_speed: float
var _solved := false


func _ready() -> void:
	_current_speed = scroll_speed
	GameState.progress_changed.connect(_on_progress_changed)
	# Covers the testing shortcut where all flags start true.
	_on_progress_changed()


func _process(delta: float) -> void:
	var mat := material_override as StandardMaterial3D
	if mat == null:
		return
	mat.uv1_offset.x = fposmod(mat.uv1_offset.x - _current_speed * delta, 1.0)


func _on_progress_changed() -> void:
	if _solved or not GameState.glasses_unlocked():
		return
	_solved = true
	if speed_change_duration <= 0.0:
		_current_speed = solved_scroll_speed
		return
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT) \
			.tween_property(self, "_current_speed", solved_scroll_speed, speed_change_duration)
