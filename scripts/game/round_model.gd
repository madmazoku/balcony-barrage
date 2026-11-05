class_name RoundModel
extends RefCounted
## Fixed-step simulation. Rendering and input do not own combat rules.
var config: GameplayConfig
var rng := RandomNumberGenerator.new()
var minions: Array[Dictionary] = []
var bolts: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var player: Vector2
var boss: Vector2
var boss_direction: float = 1.0
var elapsed: float = 0.0
var cooldown: float = 0.0
var grace: float = 0.0
var jump_remaining: float = 0.0
var furniture_timer: float = 0.0
var furniture_windup: float = 0.0
var armor: int
var broken_stages: int = 0
var released: int = 0
var kills: int = 0
var result: String = ""
var cause: String = ""
var furniture_enabled: bool
var scenario: String = "round"
var last_event: String = ""

func _init(settings: GameplayConfig) -> void:
	config = settings
	restart()

func restart(mode: String = "round") -> void:
	scenario = mode
	rng.seed = config.random_seed
	minions.clear()
	bolts.clear()
	hazards.clear()
	player = Vector2(config.arena_size.x / 2.0, config.ground_y - config.player_size.y / 2.0)
	boss = Vector2(config.arena_size.x / 2.0, config.boss_y)
	boss_direction = 1.0
	elapsed = 0.0
	cooldown = 0.0
	grace = 0.0
	jump_remaining = 0.0
	furniture_timer = config.furniture_interval_seconds
	furniture_windup = 0.0
	armor = config.armor_parts
	broken_stages = 0
	released = 0
	kills = 0
	result = ""
	cause = ""
	last_event = ""
	furniture_enabled = config.furniture_enabled
	if mode != "round":
		released = config.release_roles.size()
	match mode:
		"line":
			spawn("normal", Vector2(player.x, player.y - 150.0))
			spawn("normal", Vector2(player.x, player.y - 290.0))
		"landing":
			spawn("tank", Vector2(player.x - 100.0, config.ground_y - config.tank_size.y / 2.0 - 130.0))
			minions[0].hp = 1
		"damage":
			spawn("normal", player + Vector2(config.player_size.x, 0))
			minions[0].state = "ground"
			hazards.append({"pos": player - Vector2(0, 100), "velocity": Vector2(0, config.nut_speed), "furniture": false})
		"boss":
			pass
		"mixed":
			spawn("normal", Vector2(player.x - 190, player.y - 170))
			spawn("tank", Vector2(player.x + 200, player.y - 260))
			spawn("thrower", Vector2(player.x, player.y - 340))

func body_size(role: String) -> Vector2:
	return config.get(role + "_size")

func spawn(role: String, position: Vector2) -> void:
	minions.append({
		"role": role, "pos": position, "base_x": position.x,
		"hp": config.get(role + "_balloons"), "state": "air",
		"phase": rng.randf_range(0, TAU), "variant": rng.randi(),
		"attack": config.nut_interval_seconds, "windup": 0.0,
		"escape_direction": 1.0 if position.x >= player.x else -1.0,
	})

func shoot(direction: Vector2) -> bool:
	if result != "" or cooldown > 0.0:
		return false
	# Start outside the player's body, always cardinal.
	var offset: Vector2 = config.player_size * 0.5 + config.bolt_size
	bolts.append({"pos": player + direction * offset, "velocity": direction * config.bolt_speed})
	cooldown = config.shot_cooldown
	return true

func tick(delta: float, movement: float) -> void:
	if result != "":
		return
	elapsed += delta
	cooldown = maxf(0, cooldown - delta)
	grace = maxf(0, grace - delta)
	player.x = clampf(player.x + movement * config.player_speed * delta,
		config.player_size.x / 2, config.arena_size.x - config.player_size.x / 2)
	_update_boss(delta)
	if result != "":
		return
	while released < config.release_times.size() and elapsed >= config.release_times[released]:
		spawn(config.release_roles[released], boss + Vector2(0, config.spawn_drop))
		released += 1
	_update_bolts(delta)
	_update_minions(delta)
	_update_hazards(delta)

func _update_boss(delta: float) -> void:
	if jump_remaining > 0.0:
		jump_remaining = maxf(0, jump_remaining - delta)
		if jump_remaining == 0.0:
			broken_stages += 1
			last_event = "Тяжёлое приземление — балкон треснул"
			if broken_stages >= config.balcony_stages:
				result = "win"
				cause = "Балкон разрушен"
		return
	boss.x += boss_direction * config.boss_speed * delta
	var left: float = config.balcony_left + config.boss_size.x / 2
	var right: float = config.balcony_right - config.boss_size.x / 2
	if boss.x >= right or boss.x <= left:
		boss.x = clampf(boss.x, left, right)
		boss_direction *= -1.0
	if not furniture_enabled or released < config.release_roles.size():
		return
	if furniture_windup > 0:
		furniture_windup = maxf(0, furniture_windup - delta)
		if furniture_windup == 0:
			_throw_hazard(boss, true)
			furniture_timer = config.furniture_interval_seconds
	else:
		furniture_timer -= delta
		if furniture_timer <= 0:
			furniture_windup = config.furniture_windup_seconds

func _update_minions(delta: float) -> void:
	for enemy in minions:
		var position: Vector2 = enemy.pos
		var size: Vector2 = body_size(enemy.role)
		match enemy.state:
			"air":
				position.y += config.descent_speed * delta
				position.x = clampf(enemy.base_x + sin(elapsed * TAU / config.wind_period_seconds + enemy.phase) * config.wind_amplitude,
					size.x / 2, config.arena_size.x - size.x / 2)
				if position.y + size.y / 2 >= config.ground_y:
					position.y = config.ground_y - size.y / 2
					enemy.state = "ground"
					enemy.windup = 0.0
				elif enemy.role == "thrower":
					if enemy.windup > 0:
						enemy.windup = maxf(0, enemy.windup - delta)
						if enemy.windup == 0:
							_throw_hazard(position, false)
							enemy.attack = config.nut_interval_seconds
					else:
						enemy.attack -= delta
						if enemy.attack <= 0:
							enemy.windup = config.nut_windup_seconds
			"ground":
				position.x = move_toward(position.x, player.x, config.ground_speed * delta)
				if Rect2(position - size / 2, size).intersects(Rect2(player - config.player_size / 2, config.player_size)):
					if damage("Захват наземным миньоном"):
						enemy.state = "escape"
						enemy.escape_direction = -1.0 if position.x < player.x else 1.0
			"fall":
				position.y += config.fall_speed * delta
			"escape":
				position.x += enemy.escape_direction * config.escape_speed * delta
		enemy.pos = position
	minions = minions.filter(func(e: Dictionary) -> bool:
		return e.pos.y < config.arena_size.y + config.tank_size.y and e.pos.x > -config.tank_size.x and e.pos.x < config.arena_size.x + config.tank_size.x)

func damage(reason: String) -> bool:
	if result != "" or grace > 0:
		return false
	if armor > 0:
		armor -= 1
		grace = config.damage_grace_seconds
		last_event = reason + " — потеря брони"
	else:
		result = "lose"
		cause = reason
	return true

func _throw_hazard(origin: Vector2, is_furniture: bool) -> void:
	var speed: float = config.furniture_speed if is_furniture else config.nut_speed
	var direction: Vector2 = (player - origin).normalized()
	if not is_furniture:
		var offset: Vector2 = player - origin
		var limit: float = deg_to_rad(clampf(config.nut_max_angle_degrees, 0.0, 80.0))
		var angle: float = clampf(atan2(offset.x, offset.y), -limit, limit)
		direction = Vector2(sin(angle), cos(angle))
	hazards.append({"pos": origin, "velocity": direction * speed, "furniture": is_furniture})

func _update_hazards(delta: float) -> void:
	for index in range(hazards.size() - 1, -1, -1):
		var hazard: Dictionary = hazards[index]
		var start: Vector2 = hazard.pos
		var finish: Vector2 = start + hazard.velocity * delta
		var size: Vector2 = Vector2(config.furniture_hit_width, config.furniture_height) if hazard.furniture else config.nut_size
		var hit: float = segment_hit(start, finish, Rect2(player - (config.player_size + size) / 2, config.player_size + size))
		hazard.pos = finish
		if hit <= 1.0:
			damage("Попадание мебелью" if hazard.furniture else "Попадание гайкой")
			hazards.remove_at(index)
		elif not Rect2(-size, config.arena_size + size * 2).has_point(finish):
			hazards.remove_at(index)

func balloon_positions(enemy: Dictionary) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for index in int(enemy.hp):
		positions.append(enemy.pos + Vector2((index - (enemy.hp - 1) / 2.0) * config.balloon_spacing, -config.balloon_lift))
	return positions

func _update_bolts(delta: float) -> void:
	for index in range(bolts.size() - 1, -1, -1):
		var bolt: Dictionary = bolts[index]
		var start: Vector2 = bolt.pos
		var finish: Vector2 = start + bolt.velocity * delta
		var nearest: float = INF
		var target: Dictionary = {}
		var hit_boss: bool = false
		var projectile_size: Vector2 = config.bolt_size if is_zero_approx(bolt.velocity.x) else Vector2(config.bolt_size.y, config.bolt_size.x)
		for enemy in minions:
			if enemy.state not in ["air", "ground"]:
				continue
			var size: Vector2 = body_size(enemy.role) + projectile_size
			var hit: float = segment_hit(start, finish, Rect2(enemy.pos - size / 2, size))
			if enemy.state == "air":
				for balloon in balloon_positions(enemy):
					var reach: float = config.balloon_radius + config.bolt_size.length() / 2
					hit = minf(hit, segment_hit(start, finish, Rect2(balloon - Vector2.ONE * reach, Vector2.ONE * reach * 2)))
			if hit < nearest:
				nearest = hit
				target = enemy
		# Boss catches shots even while protected. Only an exposed idle boss takes damage.
		var boss_rect := Rect2(boss_draw_position() - (config.boss_size + projectile_size) / 2, config.boss_size + projectile_size)
		var boss_hit: float = segment_hit(start, finish, boss_rect)
		if boss_hit < nearest:
			nearest = boss_hit
			hit_boss = true
		if nearest <= 1.0:
			bolts.remove_at(index)
			if hit_boss:
				if released >= config.release_roles.size() and jump_remaining == 0:
					jump_remaining = config.boss_jump_seconds
					last_event = "Попадание в босса — ждём приземления"
			elif not target.is_empty():
				if target.state == "ground":
					target.state = "fall"
					kills += 1
				else:
					target.hp -= 1
					if target.hp == 0:
						target.state = "fall"
						kills += 1
		else:
			bolt.pos = finish
			if not Rect2(-config.bolt_size, config.arena_size + config.bolt_size * 2).has_point(finish):
				bolts.remove_at(index)

func boss_draw_position() -> Vector2:
	var progress: float = jump_remaining / config.boss_jump_seconds
	return boss - Vector2(0, sin(progress * PI) * config.boss_jump_height)

func rate() -> float:
	return kills * 60.0 / maxf(elapsed, 0.001)

static func segment_hit(start: Vector2, finish: Vector2, rectangle: Rect2) -> float:
	# Slab intersection returns the first hit along a swept projectile.
	var enter: float = 0.0
	var leave: float = 1.0
	var movement: Vector2 = finish - start
	for axis in 2:
		if is_zero_approx(movement[axis]):
			if start[axis] < rectangle.position[axis] or start[axis] > rectangle.end[axis]:
				return INF
		else:
			var first: float = (rectangle.position[axis] - start[axis]) / movement[axis]
			var second: float = (rectangle.end[axis] - start[axis]) / movement[axis]
			enter = maxf(enter, minf(first, second))
			leave = minf(leave, maxf(first, second))
			if enter > leave:
				return INF
	return enter
