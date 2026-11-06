class_name FeedbackConfig
extends Resource
## Visual timings only; never read by the combat model.
@export var enabled: bool = true
@export var shot_seconds: float
@export var shot_tilt_degrees: float
@export var shot_squash: float
@export var pop_frame_seconds: float
@export var pop_size_multiplier: float
@export var armor_flight_seconds: float
@export var armor_launch_velocity: Vector2
@export var armor_gravity: float
@export var armor_spin_radians: float
@export var armor_size_multiplier: float

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	for key in ["shot_seconds", "pop_frame_seconds", "pop_size_multiplier", "armor_flight_seconds", "armor_gravity", "armor_spin_radians", "armor_size_multiplier"]:
		if get(key) <= 0:
			errors.append("Expected positive feedback setting: " + key)
	if shot_squash < 0 or shot_squash >= 1 or shot_tilt_degrees < 0:
		errors.append("Invalid shot deformation.")
	return errors
