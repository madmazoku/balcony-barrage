extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var settings: GameplayConfig = load("res://config/gameplay.tres").duplicate(true)
	settings.wind_amplitude = 0
	settings.boss_speed = 0
	var model := RoundModel.new(settings)
	var pops: Array = []
	var pieces: Array = []
	model.balloon_popped.connect(func(position: Vector2, color: int) -> void: pops.append([position, color]))
	model.armor_removed.connect(func(part: int, stolen: bool) -> void: pieces.append([part, stolen]))
	model.restart("boss")
	model.spawn("normal", model.player - Vector2(0, 130))
	var expected_position: Vector2 = model.balloon_positions(model.minions[0])[1]
	var expected_color: int = int(model.minions[0].variant) + 1
	model.shoot(Vector2.UP)
	model.tick(0.2, 0)
	check(pops.size() == 1 and pops[0][0] == expected_position and pops[0][1] == expected_color,
		"One removed balloon must emit its old position and color exactly once.")
	model.damage("nut")
	model.damage("simultaneous nut")
	check(pieces == [[2, false]], "Grace must prevent a second detached armor piece.")
	model.restart("damage")
	model.hazards.clear()
	model.minions[0].pos = model.player
	model.tick(0.01, 0)
	check(pieces.back() == [2, true] and model.minions[0].stolen_part == 2,
		"A thief must carry the exact piece that was removed.")

	model.restart("damage")
	model.hazards.clear()
	model.armor = 0
	model.minions[0].pos = model.player
	model.tick(0.01, 0)
	check(model.result == "lose" and model.minions[0].stolen_part == -1,
		"Capturing an unarmored player must not invent a carried armor piece.")

	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var picker: OptionButton = game.get("scenario_picker")
	picker.select(4)
	game.call("_restart")
	var scene_model: RoundModel = game.get("model")
	var feedback: RoundFeedback = game.get("feedback")
	game.call("_shoot", Vector2.RIGHT)
	feedback.advance(0.04)
	var remaining: float = feedback.shot_remaining
	game.call("_shoot", Vector2.LEFT)
	check(feedback.shot_direction == Vector2.RIGHT and feedback.shot_remaining == remaining,
		"Rejected cooldown shots must not restart recoil or change its direction.")
	scene_model.damage("nut")
	check(feedback.effects.size() == 1 and feedback.effects[0].part == 2,
		"The actual scene must animate the removed visible piece.")
	var initial: Vector2 = feedback.effects[0].pos
	game.call("_toggle_pause")
	game.call("_physics_process", 0.1)
	check(feedback.effects[0].pos == initial and feedback.shot_remaining == remaining,
		"Pause must freeze all visual effects.")
	game.call("_toggle_pause")
	game.call("_physics_process", 0.1)
	check(feedback.effects[0].pos != initial and feedback.effects[0].angle != 0,
		"Resume must continue the piece flight and spin.")
	feedback.advance(feedback.settings.armor_flight_seconds)
	check(feedback.effects.is_empty() and feedback.shot_remaining == 0,
		"Expired effects must release their transient state.")
	scene_model.grace = 0
	scene_model.damage("nut")
	game.call("_restart")
	check(feedback.effects.is_empty() and feedback.shot_remaining == 0,
		"Restart must clear visuals from the previous round.")
	var saved_enabled: bool = feedback.settings.enabled
	feedback.settings.enabled = false
	game.call("_shoot", Vector2.UP)
	check(feedback.shot_remaining == 0 and not scene_model.bolts.is_empty(),
		"Disabling feedback must preserve the combat shot.")
	feedback.settings.enabled = saved_enabled
	_test_enemy_actions(game)
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("FEEDBACK_TESTS_OK")
	quit(0 if failures.is_empty() else 1)

func _test_enemy_actions(game: Node) -> void:
	var model: RoundModel = game.get("model")
	var feedback: RoundFeedback = game.get("feedback")
	var throws: Array = []
	var captures: Array = []
	model.thrower_released.connect(func(enemy: Dictionary) -> void: throws.append(enemy))
	model.armor_stolen.connect(func(part: int, enemy: Dictionary) -> void:
		captures.append([part, enemy.state, enemy.pos, enemy.stolen_part]))
	game.call("_restart")
	model.spawn("thrower", Vector2(350, 300))
	var thrower: Dictionary = model.minions[0]
	thrower.windup = 0.05
	model._update_minions(0.04)
	check(throws.is_empty() and model.hazards.is_empty(), "A held nut must not become a projectile before release.")
	model._update_minions(0.02)
	check(throws.size() == 1 and model.hazards.size() == 1 and not feedback.enemy_effect(thrower, "release").is_empty(),
		"The actual throw must emit one release event and start the matching pose.")
	model._update_minions(0.02)
	check(throws.size() == 1, "Release animation must not create repeated projectiles.")
	game.call("_restart")
	model.spawn("thrower", Vector2(350, model.config.ground_y - model.config.thrower_size.y / 2 - 0.01))
	model.minions[0].windup = 0.001
	model._update_minions(0.1)
	check(throws.size() == 1 and model.hazards.is_empty(), "Landing must cancel an unfinished throw.")
	game.call("_restart")
	model.spawn("thrower", Vector2(350, 300))
	model.minions[0].windup = 0.001
	model.bolts.append({"pos": model.minions[0].pos, "velocity": Vector2.UP * model.config.bolt_speed})
	model._update_bolts(0.001)
	model._update_minions(0.1)
	check(throws.size() == 1 and model.hazards.is_empty(), "A defeated thrower must not release a queued nut.")
	for role in ["normal", "tank", "thrower"]:
		for side in [-1.0, 1.0]:
			for armor in [1, 2, 3]:
				game.call("_restart")
				model.armor = armor
				var offset: float = (model.body_size(role).x + model.config.player_size.x) / 2 - 1
				model.spawn(role, Vector2(model.player.x + side * offset, model.config.ground_y - model.body_size(role).y / 2))
				var thief: Dictionary = model.minions[0]
				thief.state = "ground"
				model._update_minions(0.001)
				var effect: Dictionary = feedback.enemy_effect(thief, "steal")
				check(not effect.is_empty() and effect.part == armor - 1 and captures.back()[1] == "escape"
					and captures.back()[2] == thief.pos and captures.back()[3] == armor - 1,
					"Capture event must see committed thief state and the exact armor piece.")
				check(feedback.effects.filter(func(e: Dictionary) -> bool: return e.kind == "armor").is_empty(),
					"A stolen piece must not also enter free flight.")
				var pose: Dictionary = game.call("_enemy_visual_pose", thief)
				check(pose.action == role + "_capture" and pose.flip == (side > 0), "Reach must face the player on both sides.")
				game.call("_toggle_pause")
				var before: Vector2 = thief.pos
				game.call("_physics_process", 0.1)
				check(effect.age == 0 and thief.pos == before, "Pause must freeze capture and its thief.")
				game.call("_toggle_pause")
				game.call("_physics_process", 0.1)
				check(effect.age > 0 and thief.pos != before, "Capture visuals must not delay the combat escape.")
				feedback.advance(feedback.settings.capture_seconds - effect.age - 0.00001)
				var handoff: Dictionary = game.call("_carried_armor_pose", thief)
				feedback.advance(0.00002)
				var carried: Dictionary = game.call("_carried_armor_pose", thief)
				check((handoff.pos as Vector2).distance_to(carried.pos) < 0.1 and feedback.effects.is_empty(),
					"The transfer must hand off to carried armor without a position jump or stale effects.")
	game.call("_restart")
	model.spawn("normal", model.player)
	model.minions[0].state = "ground"
	model._update_minions(0.001)
	check(not feedback.effects.is_empty(), "Actual scene must create capture feedback.")
	game.call("_restart")
	check(feedback.effects.is_empty(), "Restart must clear pending capture and release effects.")
	model.armor = 0
	model.spawn("normal", model.player)
	model.minions[0].state = "ground"
	var old_count: int = captures.size()
	model._update_minions(0.001)
	check(model.result == "lose" and captures.size() == old_count and feedback.effects.filter(func(effect: Dictionary) -> bool: return effect.kind in ["armor", "steal"]).is_empty(),
		"An unarmored capture must not create a transfer or invented item.")
