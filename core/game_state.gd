extends Node
## Global game progress. Registered as an autoload named GameState,
## so any script can use GameState.hat_clicked and so on.

## Emitted whenever one of the items is clicked.
signal progress_changed

var hat_clicked := false
var beard_clicked := false
var forehead_clicked := false


## True once the hat, beard and forehead have all been clicked.
func glasses_unlocked() -> bool:
	return hat_clicked and beard_clicked and forehead_clicked


## Sets everything back to the start of the game.
func reset() -> void:
	hat_clicked = false
	beard_clicked = false
	forehead_clicked = false
	progress_changed.emit()
