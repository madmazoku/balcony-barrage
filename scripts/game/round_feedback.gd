class_name RoundFeedback
extends RefCounted
## Transient presentation state. No combat RNG, collisions or damage here.
var settings: FeedbackConfig
var effects: Array[Dictionary] = []
var defeat: Dictionary = {}
var shot_remaining: float = 0.0
var shot_direction := Vector2.UP

func _init(config: FeedbackConfig) -> void:
	settings = config

func clear() -> void:
	effects.clear()
	defeat.clear()
	shot_remaining = 0.0
	shot_direction = Vector2.UP

func shoot(direction: Vector2) -> void:
	if not settings.enabled:
		return
	shot_direction = direction
	shot_remaining = settings.shot_seconds

func recoil_weight() -> float:
	if shot_remaining <= 0:
		return 0.0
	return sin(PI * (1.0 - shot_remaining / settings.shot_seconds))

func pop(position: Vector2, variant: int, frame_count: int, angle: float = 0.0) -> void:
	if settings.enabled:
		effects.append({"kind": "pop", "pos": position, "variant": variant, "angle": angle,
			"age": 0.0, "lifetime": settings.pop_frame_seconds * frame_count})

func armor(position: Vector2, size: Vector2, part: int) -> void:
	if not settings.enabled:
		return
	var side: float = -1.0 if part % 2 == 0 else 1.0
	effects.append({"kind": "armor", "pos": position,
		"size": size * settings.armor_size_multiplier, "part": part,
		"velocity": settings.armor_launch_velocity * Vector2(side, 1),
		"angle": 0.0, "spin": settings.armor_spin_radians * side,
		"age": 0.0, "lifetime": settings.armor_flight_seconds})

func drop_weapon(position: Vector2, size: Vector2, texture: Texture2D, side: float, angle: float) -> void:
	effects.append({"kind": "weapon", "pos": position, "size": size, "texture": texture,
		"velocity": settings.defeat_weapon_launch_velocity * Vector2(-side, 1),
		"angle": angle, "spin": -side * settings.defeat_spin_radians,
		"age": 0.0, "lifetime": settings.defeat_weapon_drop_seconds})

func release(enemy: Dictionary) -> void:
	if settings.enabled and settings.enemy_actions_enabled:
		effects.append({"kind": "release", "enemy": enemy, "age": 0.0, "lifetime": settings.release_seconds})

func steal(position: Vector2, size: Vector2, part: int, enemy: Dictionary) -> void:
	if settings.enabled and settings.enemy_actions_enabled:
		effects.append({"kind": "steal", "enemy": enemy, "start_pos": enemy.pos,
			"pos": position, "size": size, "part": part,
			"age": 0.0, "lifetime": settings.capture_seconds})

func enemy_effect(enemy: Dictionary, kind: String) -> Dictionary:
	for effect in effects:
		if effect.kind == kind and is_same(effect.enemy, enemy):
			return effect
	return {}

func advance(delta: float) -> void:
	_advance_defeat(delta)
	shot_remaining = maxf(0.0, shot_remaining - delta)
	for effect in effects:
		effect.age += delta
		if effect.kind in ["armor", "weapon"]:
			effect.pos += effect.velocity * delta + Vector2(0, settings.armor_gravity * delta * delta / 2)
			effect.velocity.y += settings.armor_gravity * delta
			effect.angle += effect.spin * delta
	effects = effects.filter(func(effect: Dictionary) -> bool: return effect.age < effect.lifetime)

func begin_defeat(kind: String, source: Dictionary, origin: Transform2D, arena: Vector2, player_height: float, escape_speed: float) -> void:
	if not settings.enabled or not settings.defeat_enabled or not defeat.is_empty():
		return
	if kind == "capture" and (source.get("enemy", {}) as Dictionary).is_empty():
		return
	var velocity: Vector2 = source.get("velocity", Vector2.ZERO)
	var side: float = signf(velocity.x)
	if is_zero_approx(side):
		side = signf(origin.origin.x - (source.get("pos", origin.origin) as Vector2).x)
	if is_zero_approx(side):
		side = 1.0
	defeat = {"kind": kind, "age": 0.0, "done": false, "origin": origin.origin,
		"pos": origin.origin, "initial_angle": origin.get_rotation(), "angle": origin.get_rotation(),
		"scale": origin.get_scale(), "arena": arena, "player_height": player_height,
		"side": side, "velocity": settings.defeat_launch_velocity * Vector2(side, 1), "distance": 0.0}
	if kind == "capture":
		defeat.source_enemy = source.get("enemy", {})
		defeat.carrier = (defeat.source_enemy as Dictionary).duplicate()
		defeat.carrier.pos = source.get("pos", origin.origin)
		defeat.carrier.state = "escape"
		defeat.carrier.windup = 0.0
		defeat.carrier.stolen_part = -1
		defeat.side = source.get("direction", 1.0)
		defeat.carrier.escape_direction = defeat.side
		defeat.escape_speed = escape_speed

func result_ready() -> bool:
	return defeat.is_empty() or defeat.done

func _advance_defeat(delta: float) -> void:
	if defeat.is_empty() or defeat.done:
		return
	var old_age: float = defeat.age
	defeat.age += delta
	if defeat.kind == "capture":
		var moving_time: float = maxf(0, defeat.age - settings.defeat_transfer_seconds) - maxf(0, old_age - settings.defeat_transfer_seconds)
		var distance: float = defeat.escape_speed * moving_time
		defeat.distance += distance
		defeat.carrier.pos.x += defeat.side * distance
		var blend: float = smoothstep(0, settings.defeat_transfer_seconds, defeat.age)
		var angle: float = -defeat.side * deg_to_rad(settings.defeat_carry_angle_degrees)
		var center: Vector2 = defeat.carrier.pos + settings.defeat_carry_offset * Vector2(defeat.side, 1)
		var target: Vector2 = center + Vector2(0, defeat.player_height / 2).rotated(angle)
		defeat.pos = (defeat.origin as Vector2).lerp(target, blend)
		defeat.angle = lerp_angle(defeat.initial_angle, angle, blend)
		defeat.done = defeat.carrier.pos.x < -settings.defeat_offscreen_margin or defeat.carrier.pos.x > defeat.arena.x + settings.defeat_offscreen_margin
	else:
		defeat.pos += defeat.velocity * delta + Vector2(0, settings.defeat_gravity * delta * delta / 2)
		defeat.velocity.y += settings.defeat_gravity * delta
		defeat.angle += settings.defeat_spin_radians * defeat.side * delta
		var margin: float = settings.defeat_offscreen_margin
		defeat.done = defeat.pos.x < -margin or defeat.pos.x > defeat.arena.x + margin or defeat.pos.y > defeat.arena.y + margin
	defeat.done = (defeat.done and defeat.age >= settings.defeat_min_seconds) or defeat.age >= settings.defeat_max_seconds
