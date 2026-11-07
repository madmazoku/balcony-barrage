class_name RoundMotion
extends RefCounted
## Frame phase follows measured movement; never changes or predicts the model.
var settings: MotionConfig
var player_x: float
var player_distance: float = 0.0
var player_moving: bool = false
var actors: Array[Dictionary] = []
var boss_x: float
var boss_distance: float = 0.0
var boss_moving: bool = false

func _init(config: MotionConfig) -> void:
	settings = config

func reset(model: RoundModel) -> void:
	player_x = model.player.x
	player_distance = 0.0
	player_moving = false
	actors.clear()
	boss_x = model.boss.x
	boss_distance = 0.0
	boss_moving = false
	advance(model)

func begin_step() -> void:
	player_moving = false
	boss_moving = false
	for actor in actors:
		actor.moving = false

func track_player(position: Vector2) -> void:
	var distance: float = absf(position.x - player_x)
	player_moving = player_moving or not is_zero_approx(distance)
	player_distance = fposmod(player_distance + distance, settings.stride_pixels["player"])
	player_x = position.x

func advance(model: RoundModel) -> void:
	track_player(model.player)
	if settings.boss_enabled:
		var walking: bool = model.jump_remaining <= 0 and not model.boss_falling and model.result == ""
		var distance: float = absf(model.boss.x - boss_x) if walking else 0.0
		boss_moving = not is_zero_approx(distance)
		boss_distance = fposmod(boss_distance + distance, settings.stride_pixels["boss"]) if walking else 0.0
		boss_x = model.boss.x
	actors = actors.filter(func(actor: Dictionary) -> bool:
		return model.minions.any(func(enemy: Dictionary) -> bool: return is_same(actor.enemy, enemy)))
	for enemy in model.minions:
		var actor: Dictionary = _actor(enemy)
		if actor.is_empty():
			actor = {"enemy": enemy, "pos": enemy.pos, "distance": 0.0, "moving": false, "state": enemy.state}
			actors.append(actor)
		var walking: bool = enemy.state in ["ground", "escape"] and actor.state in ["ground", "escape"]
		var distance: float = absf(enemy.pos.x - actor.pos.x) if walking else 0.0
		actor.moving = actor.moving or not is_zero_approx(distance)
		actor.distance = fposmod(actor.distance + distance, settings.stride_pixels[enemy.role]) if walking else 0.0
		actor.pos = enemy.pos
		actor.state = enemy.state
	if model.result != "" or model.boss_falling:
		player_moving = false
		for actor in actors:
			actor.moving = false

func _actor(enemy: Dictionary) -> Dictionary:
	for actor in actors:
		if is_same(actor.enemy, enemy):
			return actor
	return {}

func phase(role: String, enemy: Dictionary = {}) -> float:
	if not settings.enabled:
		return -1.0
	if role == "boss":
		return boss_distance / settings.stride_pixels[role] if settings.boss_enabled and boss_moving else -1.0
	if role == "player":
		return player_distance / settings.stride_pixels[role] if player_moving else -1.0
	var actor: Dictionary = _actor(enemy)
	return actor.distance / settings.stride_pixels[role] if not actor.is_empty() and actor.moving else -1.0

func frame_index(role: String, count: int, enemy: Dictionary = {}) -> int:
	var progress: float = phase(role, enemy)
	return mini(count - 1, int(progress * count)) if progress >= 0 else -1

func bob(role: String, enemy: Dictionary = {}) -> float:
	var progress: float = phase(role, enemy)
	return -absf(sin(TAU * progress * 2)) * settings.bob_pixels[role] if progress >= 0 else 0.0
