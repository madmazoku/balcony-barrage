class_name RoundFeedback
extends RefCounted
## Transient presentation state. No combat RNG, collisions or damage here.
var settings: FeedbackConfig
var effects: Array[Dictionary] = []
var shot_remaining: float = 0.0
var shot_direction := Vector2.UP

func _init(config: FeedbackConfig) -> void:
	settings = config

func clear() -> void:
	effects.clear()
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

func pop(position: Vector2, variant: int, frame_count: int) -> void:
	if settings.enabled:
		effects.append({"kind": "pop", "pos": position, "variant": variant,
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
	shot_remaining = maxf(0.0, shot_remaining - delta)
	for effect in effects:
		effect.age += delta
		if effect.kind == "armor":
			effect.pos += effect.velocity * delta + Vector2(0, settings.armor_gravity * delta * delta / 2)
			effect.velocity.y += settings.armor_gravity * delta
			effect.angle += effect.spin * delta
	effects = effects.filter(func(effect: Dictionary) -> bool: return effect.age < effect.lifetime)
