class_name ProjectileVisualConfig
extends Resource
## Optional pack-owned rendering; never used by RoundModel.
@export var enabled: bool = true
@export var trail_length: float
@export var trail_samples: int
@export var tail_scale: float
@export var trail_opacity: float
@export var trail_tint: Color
@export var glint_period: float
@export var glint_strength: float
@export var glint_power: float
@export var glint_tint: Color

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	for key in ["trail_length", "glint_period", "glint_power"]:
		var value: float = get(key)
		if not is_finite(value) or value <= 0:
			errors.append("Invalid projectile visual setting: " + key)
	if trail_samples < 2 or trail_samples > 32 or not is_finite(tail_scale) or tail_scale <= 0 or tail_scale > 1:
		errors.append("Invalid projectile trail sampling/scale.")
	if not is_finite(trail_opacity) or trail_opacity < 0 or trail_opacity > 1 or not is_finite(glint_strength) or glint_strength < 0:
		errors.append("Invalid projectile trail opacity/glint.")
	for tint in [trail_tint, glint_tint]:
		if not Vector4(tint.r, tint.g, tint.b, tint.a).is_finite() or minf(tint.r, minf(tint.g, tint.b)) < 0 or tint.a < 0 or tint.a > 1:
			errors.append("Invalid projectile visual tint.")
	return errors
