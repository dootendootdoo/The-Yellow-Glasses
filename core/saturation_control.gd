class_name SaturationControl
extends Node
## Add as a child of a Sprite3D or AnimatedSprite3D to control its color
## saturation and outline glow. Saturation: 0 is grayscale, 1 is normal.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform float saturation = 1.0;

uniform float glow = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float glow_width = 4.0;
uniform float glow_intensity = 2.0;
uniform float pulse_speed = 2.0;
uniform float pulse_amount = 0.3;

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	vec4 color = tex * COLOR;
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 base = mix(vec3(gray), color.rgb, saturation);

	float outline = 0.0;
	if (glow > 0.0) {
		vec2 step_uv = glow_width / vec2(textureSize(texture_albedo, 0));
		for (int i = 0; i < 16; i++) {
			float angle = float(i) * 6.2831853 / 16.0;
			vec2 dir = vec2(cos(angle), sin(angle)) * step_uv;
			outline = max(outline, texture(texture_albedo, UV + dir).a);
			outline = max(outline, texture(texture_albedo, UV + dir * 0.5).a);
		}
		outline *= 1.0 - tex.a;
		float pulse = 1.0 - pulse_amount * (0.5 + 0.5 * sin(TIME * pulse_speed));
		outline *= glow * pulse * glow_color.a * COLOR.a;
	}

	vec3 glow_rgb = glow_color.rgb * glow_intensity;
	float total = color.a + outline;
	ALBEDO = mix(glow_rgb, base, color.a / max(total, 0.0001));
	ALPHA = clamp(total, 0.0, 1.0);
}
"""

@export_range(0.0, 2.0, 0.01) var saturation: float = 1.0: set = set_saturation

@export_group("Glow")
@export var glow_color: Color = Color(1.0, 0.85, 0.4)
@export_range(0.0, 32.0, 0.5) var glow_width: float = 2.0
@export_range(0.0, 10.0, 0.1) var glow_intensity: float = 2.0
@export var pulse_speed: float = 2.0
@export_range(0.0, 1.0, 0.01) var pulse_amount: float = 0.3

@export_group("Glasses Unlock")
## When on, fades to unlock_saturation once the hat, beard and forehead are all clicked.
@export var react_to_unlock: bool = false
@export_range(0.0, 2.0, 0.01) var unlock_saturation: float = 0.0
@export var unlock_duration: float = 1.0
## When on, the outline glow fades in once the puzzle is solved.
@export var glow_on_unlock: bool = false

## 0 = no outline, 1 = full outline. Tween this with glow_to().
var glow: float = 0.0: set = set_glow

var _sprite: SpriteBase3D
var _material: ShaderMaterial
var _tween: Tween
var _glow_tween: Tween
var _unlocked := false


func _ready() -> void:
	_sprite = get_parent() as SpriteBase3D
	if _sprite == null:
		push_error("SaturationControl: parent must be a Sprite3D or AnimatedSprite3D.")
		return

	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
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

	_material.set_shader_parameter("glow_color", glow_color)
	_material.set_shader_parameter("glow_width", glow_width)
	_material.set_shader_parameter("glow_intensity", glow_intensity)
	_material.set_shader_parameter("pulse_speed", pulse_speed)
	_material.set_shader_parameter("pulse_amount", pulse_amount)
	set_glow(glow)

	if react_to_unlock or glow_on_unlock:
		GameState.progress_changed.connect(_on_progress_changed)
		# Covers the testing shortcut where all flags start true.
		_on_progress_changed()


func set_saturation(value: float) -> void:
	saturation = value
	_apply_saturation()


func set_glow(value: float) -> void:
	glow = value
	if _material != null:
		_material.set_shader_parameter("glow", glow)


## Smoothly changes saturation to `target` over `duration` seconds.
func fade_to(target: float, duration: float = 1.0) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "saturation", target, duration)
	return _tween


## Smoothly changes the outline glow to `target` over `duration` seconds.
func glow_to(target: float, duration: float = 1.0) -> Tween:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(self, "glow", target, duration)
	return _glow_tween


func _on_progress_changed() -> void:
	if _unlocked or not GameState.glasses_unlocked():
		return
	_unlocked = true
	if react_to_unlock:
		fade_to(unlock_saturation, unlock_duration)
	if glow_on_unlock:
		glow_to(1.0, unlock_duration)


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
