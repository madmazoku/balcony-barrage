extends SceneTree

func _initialize() -> void:
	var gameplay := load("res://config/gameplay.tres") as GameplayConfig
	var presentation := load("res://config/presentation.tres") as PresentationConfig
	var failures: Array[String] = []
	var controls := load("res://config/controls.tres") as ControlsConfig
	if controls == null:
		push_error("Unable to load controls config.")
		quit(1)
		return
	if controls.stick_deadzone <= 0 or controls.stick_deadzone >= 1:
		failures.append("Stick deadzone must be strictly between 0 and 1.")
	if controls.drag_threshold <= 0 or controls.tap_seconds <= 0 or controls.ground_tap_height <= 0:
		failures.append("Touch thresholds must be positive.")
	if gameplay == null or presentation == null or presentation.active_pack == null:
		push_error("Unable to load gameplay or active presentation pack.")
		quit(1)
		return
	if gameplay.normal_balloons != 2 or gameplay.tank_balloons != 4 or gameplay.thrower_balloons != 1:
		failures.append("Balloon counts differ from the approved three roles.")
	if gameplay.release_times.size() != gameplay.release_roles.size() or gameplay.release_times.is_empty():
		failures.append("Wave requires matching nonempty time and role arrays.")
	var previous_time := -1.0
	for release_time in gameplay.release_times:
		if release_time < 0.0 or release_time < previous_time:
			failures.append("Wave times must be nonnegative and ordered.")
		previous_time = release_time
	for role in gameplay.release_roles:
		if role not in ["normal", "tank", "thrower"]:
			failures.append("Unknown minion role: " + role)
	for property in ["player_speed", "bolt_speed", "shot_cooldown", "damage_grace_seconds",
			"descent_speed", "ground_speed", "wind_period_seconds", "nut_interval_seconds",
			"nut_windup_seconds", "nut_speed", "boss_speed", "balcony_stages",
			"boss_jump_seconds", "furniture_interval_seconds", "furniture_windup_seconds",
			"furniture_speed", "furniture_hit_width"]:
		if gameplay.get(property) <= 0:
			failures.append("Expected positive setting: " + property)
	if gameplay.nut_max_angle_degrees < 0.0 or gameplay.nut_max_angle_degrees > 80.0:
		failures.append("Nut aiming half-angle must be between 0 and 80 degrees.")
	if gameplay.armor_parts < 0 or gameplay.wind_amplitude < 0:
		failures.append("Armor and wind amplitude must be nonnegative.")
	var pack := presentation.active_pack
	if pack.pack_id == &"" or pack.balloon_palette.is_empty():
		failures.append("Pack requires ID and balloon palette.")
	for role in ["player", "boss", "normal", "tank", "thrower"]:
		if not pack.display_names.has(role) or pack.display_names[role].is_empty():
			failures.append("Missing display name: " + role)
	for key in ["player", "boss", "normal", "tank", "thrower", "background", "ground",
			"balcony", "bolt", "nut", "armor", "furniture", "text"]:
		if not pack.colors.has(key):
			failures.append("Missing prototype color: " + key)
	if pack.readiness != "prototype":
		failures.append("Static/animated pack contracts require phase 4 validator extension.")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("FOUNDATION_OK — gameplay and active pack loaded")
	quit(0 if failures.is_empty() else 1)
