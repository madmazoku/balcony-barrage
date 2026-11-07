class_name BossActions
extends RefCounted
## Reads model state and actual events; no simulation writes or combat RNG.
var settings: BossActionConfig
var release_age: float = INF
var throw_age: float = INF
var landing_age: float = INF

func _init(config: BossActionConfig) -> void:
	settings = config

func clear() -> void:
	release_age = INF
	throw_age = INF
	landing_age = INF

func trigger(kind: String) -> void:
	if not settings.enabled:
		return
	match kind:
		"release": release_age = 0.0
		"throw": throw_age = 0.0
		"land": landing_age = 0.0

func advance(delta: float) -> void:
	release_age += delta
	throw_age += delta
	landing_age += delta

func pose(model: RoundModel) -> Dictionary:
	var pose: Dictionary = {"action": "", "scale": Vector2.ONE, "angle": 0.0,
		"sack": model.released < model.config.release_times.size(), "sack_weight": 0.0, "furniture": false, "lift": 0.0}
	if not settings.enabled or model.result != "":
		return pose
	if model.boss_falling:
		pose.action = "air"
		pose.angle = deg_to_rad(settings.fall_tilt_degrees) * model.boss_direction
		return pose
	if model.jump_remaining > 0:
		pose.action = "air"
		var weight: float = sin(PI * model.jump_remaining / model.config.boss_jump_seconds)
		pose.scale = Vector2(1 - settings.jump_stretch * weight, 1 + settings.jump_stretch * weight)
		return pose
	if landing_age < settings.landing_seconds:
		pose.action = "land"
		var weight: float = 1 - landing_age / settings.landing_seconds
		pose.scale = Vector2(1 + settings.landing_squash * weight, 1 - settings.landing_squash * weight)
		return pose
	if model.furniture_enabled and model.furniture_windup > 0:
		pose.action = "hold"
		pose.furniture = true
		pose.lift = 1 - model.furniture_windup / model.config.furniture_windup_seconds
		if pose.lift > 1 - settings.swing_fraction:
			pose.action = "release"
		return pose
	if throw_age < settings.throw_seconds:
		pose.action = "release"
		return pose
	pose.sack = model.released < model.config.release_times.size() or release_age < settings.release_seconds
	if release_age < settings.release_seconds:
		pose.action = "release"
		pose.sack_weight = sin(PI * release_age / settings.release_seconds)
	elif model.released < model.config.release_times.size():
		var until: float = model.config.release_times[model.released] - model.elapsed
		if until >= 0 and until <= settings.reach_seconds:
			pose.action = "reach"
			pose.sack_weight = 1 - until / settings.reach_seconds
	return pose
