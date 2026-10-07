extends SpriteBase3D
## Hidden at the start. Appears once the hat, beard and forehead are all clicked.


func _ready() -> void:
	visible = false
	GameState.progress_changed.connect(_on_progress_changed)
	# Covers the testing shortcut where all flags start true.
	_on_progress_changed()


func _on_progress_changed() -> void:
	if GameState.glasses_unlocked():
		visible = true
