class_name SaturationControl
extends Node
## Add as a child of a Sprite3D or AnimatedSprite3D to control its color
## saturation. 0 is grayscale, 1 is normal, above 1 is extra saturated.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap;
uniform float saturation = 1.0;

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	vec4 color = tex * COLOR;
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(gray), color.rgb, saturation);
	ALPHA = color.a;
}
"""


@export_range(0.0, 2.0, 0.01) var saturation: float = 1.0: set = set_saturation

var _sprite: SpriteBase3D
var _material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	_sprite = get_parent() as SpriteBase3D
	if _sprite == null:
		push_error("SaturationControl: parent must be a Sprite3D or AnimatedSprite3D.")
		return

	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material.shader = shader

	_sprite.material_override = _material

	# A custom material doesn't receive the sprite's texture automatically,
	# so pass it in whenever the shown frame changes.
	if _sprite is AnimatedSprite3D:
		var animated := _sprite as AnimatedSprite3D
		animated.frame_changed.connect(_update_texture)
		animated.animation_changed.connect(_update_texture)
		animated.sprite_frames_changed.connect(_update_texture)
	elif _sprite is Sprite3D:
		(_sprite as Sprite3D).texture_changed.connect(_update_texture)

	_update_texture()
	_apply_saturation()


func set_saturation(value: float) -> void:
	saturation = value
	_apply_saturation()


## Smoothly changes saturation to `target` over `duration` seconds.
## Returns the tween, so you can `await fade_to(...).finished`.
func fade_to(target: float, duration: float = 1.0) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "saturation", target, duration)
	return _tween


func _apply_saturation() -> void:
	if _material != null:
		_material.set_shader_parameter("saturation", saturation)


func _update_texture() -> void:
	if _material != null:
		_material.set_shader_parameter("texture_albedo", _current_texture())


func _current_texture() -> Texture2D:
	if _sprite is Sprite3D:
		return (_sprite as Sprite3D).texture
	if _sprite is AnimatedSprite3D:
		var animated := _sprite as AnimatedSprite3D
		var frames := animated.sprite_frames
		if frames != null and frames.has_animation(animated.animation) \
				and animated.frame < frames.get_frame_count(animated.animation):
			return frames.get_frame_texture(animated.animation, animated.frame)
	return null
