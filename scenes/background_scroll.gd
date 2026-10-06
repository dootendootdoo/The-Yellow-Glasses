extends MeshInstance3D

# How fast the image moves, in "image widths per second".
# 0.02 = one full loop every 50 seconds.
@export var scroll_speed: float = 0.01

func _process(delta: float) -> void:
	var mat := material_override as StandardMaterial3D
	mat.uv1_offset.x = fposmod(mat.uv1_offset.x - scroll_speed * delta, 1.0)
