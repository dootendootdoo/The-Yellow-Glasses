extends PickableAnimatedSprite3D

var has_been_clicked := false

func _ready() -> void:
	visible = true
	stop()
	frame = 0

## Refuses clicks after the first one.
func accepts_click() -> bool:
	return not has_been_clicked

func on_click() -> void:
	has_been_clicked = true
	play(&"default")
	GameState.hat_clicked = true
	GameState.progress_changed.emit()

## Can be clicked again, as before the game.
func reset() -> void:
	has_been_clicked = false
	stop()
	frame = 0
