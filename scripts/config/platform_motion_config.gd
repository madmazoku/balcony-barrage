class_name PlatformMotionConfig
extends Resource
## Shared presentation timings and trajectories for all packs.
@export var debris_count: int
@export var debris_size: Vector2
@export var debris_velocity: Vector2
@export var debris_seconds: float
@export var debris_gravity: float
@export var sag_pixels: float
@export var sag_seconds: float
@export var hinge_seconds: float
@export var hinge_degrees: float
@export var section_delay: float
@export var fall_speed: float
@export var fall_gravity: float
@export var fall_spin_degrees: float
@export var collapse_seconds: float

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	for key in ["debris_seconds", "debris_gravity", "sag_pixels", "sag_seconds", "hinge_seconds", "hinge_degrees",
			"section_delay", "fall_speed", "fall_gravity", "fall_spin_degrees", "collapse_seconds"]:
		if not is_finite(get(key)) or get(key) <= 0.0:
			errors.append("Expected positive platform setting: " + key)
	if debris_count < 2 or not debris_size.is_finite() or debris_size.x <= 0.0 or debris_size.y < debris_size.x \
			or not debris_velocity.is_finite() or collapse_seconds <= hinge_seconds + section_delay:
		errors.append("Invalid platform motion dimensions or timing.")
	return errors
