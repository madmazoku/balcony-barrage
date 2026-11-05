extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	var config: GameplayConfig = load("res://config/gameplay.tres").duplicate(true)
	config.wind_amplitude = 0
	config.boss_speed = 0
	var model := RoundModel.new(config)
	model.restart("boss")
	model.spawn("normal", model.player - Vector2(0, 130))
	model.spawn("tank", model.player - Vector2(0, 240))
	check(model.shoot(Vector2.UP), "First shot must fire.")
	check(not model.shoot(Vector2.LEFT), "All directions must share cooldown.")
	model.tick(0.2, 0)
	check(model.minions[0].hp == 1 and model.minions[1].hp == 4, "A swept bolt must only damage the first target.")
	check(model.bolts.is_empty(), "The hitting bolt must be consumed.")
	# A large projectile step must not tunnel through targets.
	model.cooldown = 0
	model.shoot(Vector2.UP)
	model.tick(0.5, 0)
	check(model.kills == 1 and model.minions[1].hp == 4, "Last balloon counts exactly once, without piercing.")
	model.tick(0.5, 0)
	check(model.kills == 1, "Falling enemy must not count twice.")

	model.restart("landing")
	model.tick(4.0, 0)
	check(model.minions[0].state == "ground", "Living minion must land and detach balloons.")
	model.player.x = model.minions[0].pos.x - 150
	model.shoot(Vector2.RIGHT)
	model.tick(0.2, 0)
	check(model.kills == 1 and model.minions[0].state == "fall", "Ground tank must take one shot.")

	model.restart("boss")
	model.spawn("normal", model.player - Vector2(0, 130))
	model.minions[0].hp = 1
	model.shoot(Vector2.UP)
	model.tick(0.2, 0)
	model.tick(2.0, 0)
	check(model.minions.is_empty() and model.kills == 1, "Shot down enemy must leave screen without landing.")

	model.restart("damage")
	model.hazards.clear()
	model.minions[0].pos = model.player
	model.tick(0.01, 0)
	check(model.armor == config.armor_parts - 1 and model.minions[0].state == "escape", "Contact steals one armor part and escapes.")
	check(not model.damage("simultaneous nut"), "Simultaneous sources must respect grace.")
	check(model.kills == 0, "Escaping thief is not a kill.")
	model.grace = 0
	model.armor = 0
	model.damage("nut")
	check(model.result == "lose", "Unarmored nut must end round.")
	model.restart("damage")
	model.hazards.clear()
	model.armor = 0
	model.minions[0].pos = model.player
	model.tick(0.01, 0)
	check(model.result == "lose" and model.cause.contains("Захват"), "Unarmored capture must end round.")

	model.restart()
	model.bolts.append({"pos": model.boss + Vector2(0, 70), "velocity": Vector2.UP * config.bolt_speed})
	model.tick(0.1, 0)
	check(model.jump_remaining == 0 and model.broken_stages == 0, "Full bag must protect boss.")
	model.restart("boss")
	for stage in config.balcony_stages:
		model.bolts.append({"pos": model.boss + Vector2(0, 70), "velocity": Vector2.UP * config.bolt_speed})
		model.tick(0.1, 0)
		check(model.broken_stages == stage, "Hit must wait for boss landing.")
		model.bolts.append({"pos": model.boss_draw_position() + Vector2(0, 45), "velocity": Vector2.UP * config.bolt_speed})
		model.tick(0.1, 0)
		model.tick(config.boss_jump_seconds, 0)
		check(model.broken_stages == stage + 1, "Each jump must break exactly one stage.")
	check(model.result == "win", "Final landing must win.")
	var final_time: float = model.elapsed
	model.tick(10, 1)
	check(model.elapsed == final_time, "Round must freeze at the final result.")

	model.restart("boss")
	model.furniture_enabled = true
	model.tick(config.furniture_interval_seconds, 0)
	check(model.furniture_windup > 0, "Furniture must have visible warning.")
	model.tick(config.furniture_windup_seconds, 0)
	check(not model.hazards.is_empty() or model.armor < config.armor_parts, "Warned furniture must actually be thrown.")
	model.restart()
	var replay := RoundModel.new(config)
	for frame in 600:
		var movement: float = sin(frame / 60.0)
		if frame % 30 == 0:
			model.shoot(Vector2.UP)
			replay.shoot(Vector2.UP)
		model.tick(1.0 / 60, movement)
		replay.tick(1.0 / 60, movement)
	check(model.minions == replay.minions and model.hazards == replay.hazards and model.kills == replay.kills, "Seed and input replay must be deterministic.")
	# Exercise actual thrower windup near the ground with the player far to either side.
	for side in [-1.0, 1.0]:
		model.restart("boss")
		model.player.x = config.arena_size.x / 2.0 + side * 500.0
		model.spawn("thrower", Vector2(config.arena_size.x / 2.0, model.player.y - 40.0))
		model.minions[0].windup = 0.001
		model.tick(0.01, 0)
		check(model.hazards.size() == 1, "Airborne thrower must release a nut after windup.")
		var velocity: Vector2 = model.hazards[0].velocity
		var angle: float = absf(rad_to_deg(atan2(velocity.x, velocity.y)))
		check(is_equal_approx(angle, config.nut_max_angle_degrees), "Low thrower must clamp aim on both sides of vertical.")
		check(velocity.y > 0 and signf(velocity.x) == side, "Clamped nut must travel down toward the player's side.")
		check(is_equal_approx(velocity.length(), config.nut_speed), "Clamping must preserve nut speed.")
	model.restart("boss")
	model.spawn("thrower", model.player - Vector2(20, 200))
	model.minions[0].windup = 0.001
	model.tick(0.01, 0)
	var aimed: Vector2 = model.hazards[0].velocity.normalized()
	var expected: Vector2 = (model.player - model.minions[0].pos).normalized()
	check(aimed.is_equal_approx(expected), "Targets within the cone must retain direct aim.")
	var saved_angle: float = config.nut_max_angle_degrees
	config.nut_max_angle_degrees = 0.0
	model.restart("boss")
	model.spawn("thrower", model.player - Vector2(200, 100))
	model.minions[0].windup = 0.001
	model.tick(0.01, 0)
	check(is_zero_approx(model.hazards[0].velocity.x), "Zero cone angle must produce a vertical throw.")
	config.nut_max_angle_degrees = saved_angle
	call_deferred("_test_scene")

func _test_scene() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
	var model: RoundModel = game.get("model")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_D
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	check(not model.bolts.is_empty() and model.bolts[0].velocity.x > 0, "Real scene input must fire horizontally while moving.")
	for key in [KEY_D, KEY_SPACE]:
		event = InputEventKey.new()
		event.physical_keycode = key
		event.pressed = false
		Input.parse_input_event(event)
	var picker: OptionButton = game.get("scenario_picker")
	picker.select(4)
	picker.item_selected.emit(4)
	check(model.scenario == "boss" and model.released == model.config.release_roles.size(), "Scenario control must reset the actual game.")
	game.call("_restart")
	check(model.kills == 0 and model.result == "", "Restart entry must reset score and result.")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("ROUND_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
