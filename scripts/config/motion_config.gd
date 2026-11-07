class_name MotionConfig
extends Resource
## Presentation distances and bounce only; no speeds or combat timings.
@export var enabled: bool = true
@export var boss_enabled: bool = false
@export var stride_pixels: Dictionary[String, float]
@export var bob_pixels: Dictionary[String, float]

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var roles: Array[String] = ["player", "normal", "tank", "thrower"]
	if boss_enabled:
		roles.append("boss")
	for role in roles:
		if stride_pixels.get(role, 0.0) <= 0:
			errors.append("Expected positive stride distance: " + role)
		if not bob_pixels.has(role) or bob_pixels[role] < 0:
			errors.append("Expected nonnegative running bounce: " + role)
	return errors
