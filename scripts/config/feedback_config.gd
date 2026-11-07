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

@export_group("Enemy actions")
@export var enemy_actions_enabled: bool = false
@export var release_seconds: float
@export var capture_seconds: float
@export var armor_transfer_seconds: float
@export var windup_tilt_degrees: float
@export var capture_tilt_degrees: float
@export var capture_reach_fraction: float
@export var carry_offset: Vector2
@export var carry_size: Vector2

@export_group("Defeat presentation")
@export var defeat_enabled: bool = false
@export var defeat_transfer_seconds: float
@export var defeat_min_seconds: float
@export var defeat_max_seconds: float
@export var defeat_offscreen_margin: float
@export var defeat_launch_velocity: Vector2
@export var defeat_gravity: float
@export var defeat_spin_radians: float
@export var defeat_carry_offset: Vector2
@export var defeat_carry_angle_degrees: float
@export var defeat_weapon_drop_seconds: float
@export var defeat_weapon_launch_velocity: Vector2

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	for key in ["shot_seconds", "pop_frame_seconds", "pop_size_multiplier", "armor_flight_seconds", "armor_gravity", "armor_spin_radians", "armor_size_multiplier"]:
		if get(key) <= 0:
			errors.append("Expected positive feedback setting: " + key)
	if shot_squash < 0 or shot_squash >= 1 or shot_tilt_degrees < 0:
		errors.append("Invalid shot deformation.")
	if enemy_actions_enabled:
		for key in ["release_seconds", "capture_seconds", "armor_transfer_seconds"]:
			if get(key) <= 0:
				errors.append("Expected positive enemy animation setting: " + key)
		if armor_transfer_seconds > capture_seconds or capture_reach_fraction <= 0 or capture_reach_fraction >= 1:
			errors.append("Armor transfer and reach must fit inside capture animation.")
		if carry_size.x <= 0 or carry_size.y <= 0 or windup_tilt_degrees < 0 or capture_tilt_degrees < 0:
			errors.append("Invalid enemy animation geometry.")
	if defeat_enabled:
		for key in ["defeat_transfer_seconds", "defeat_min_seconds", "defeat_max_seconds", "defeat_offscreen_margin", "defeat_gravity", "defeat_weapon_drop_seconds"]:
			if get(key) <= 0:
				errors.append("Expected positive defeat visual setting: " + key)
		if defeat_max_seconds <= maxf(defeat_transfer_seconds, defeat_min_seconds) or defeat_launch_velocity.x <= 0 or defeat_launch_velocity.y >= 0:
			errors.append("Invalid defeat timing or launch velocity.")
	return errors
