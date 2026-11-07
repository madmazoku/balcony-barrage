class_name BossActionConfig
extends Resource
## Visual settings only; attack schedules and damage stay in GameplayConfig.
@export var enabled: bool = true
@export var reach_seconds: float = 0.55
@export var release_seconds: float = 0.32
@export var throw_seconds: float = 0.26
@export var landing_seconds: float = 0.28
@export var jump_stretch: float = 0.08
@export var landing_squash: float = 0.16
@export var sack_offset: Vector2 = Vector2(0.38, 0.25)
@export var sack_size: Vector2 = Vector2(0.40, 0.58)
@export var sack_pulse: float = 0.12
@export var furniture_hold_offset: Vector2 = Vector2(0.13, -0.48)
@export var furniture_lift_offset: Vector2 = Vector2(0.35, -0.02)
@export var walking_split_fraction: float = 0.76171875
@export var swing_fraction: float = 0.20
@export var lift_fraction: float = 0.35
@export var fall_tilt_degrees: float = 12.0

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	for key in ["reach_seconds", "release_seconds", "throw_seconds", "landing_seconds"]:
		if get(key) <= 0:
			errors.append("Expected positive boss visual duration: " + key)
	for key in ["jump_stretch", "landing_squash", "sack_pulse"]:
		if get(key) < 0 or get(key) >= 0.5:
			errors.append("Invalid boss deformation: " + key)
	if swing_fraction <= 0 or swing_fraction >= 1 or lift_fraction <= 0 or lift_fraction >= 1 - swing_fraction:
		errors.append("Invalid furniture lift/swing fractions.")
	if walking_split_fraction <= 0 or walking_split_fraction >= 1:
		errors.append("Boss walking seam must lie inside the registered frame.")
	if sack_size.x <= 0 or sack_size.y <= 0:
		errors.append("Boss sack requires positive dimensions.")
	return errors
