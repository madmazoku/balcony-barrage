extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	(game.get("scenario_picker") as OptionButton).select(4)
	game.call("_restart")
	var model: RoundModel = game.get("model")
	var feedback: RoundFeedback = game.get("feedback")
	var events: Array = []
	model.player_defeated.connect(func(kind: String, source: Dictionary) -> void: events.append([kind, source]))
	for role in ["normal", "tank", "thrower"]:
		for side in [-1.0, 1.0]:
			game.call("_restart")
			model.armor = 0
			model.spawn(role, Vector2(model.player.x + side * ((model.body_size(role).x + model.config.player_size.x) / 2 - 1), model.config.ground_y - model.body_size(role).y / 2))
			var enemy: Dictionary = model.minions[0]
			enemy.state = "ground"
			model._update_minions(0.001)
			check(model.result == "lose" and events.back()[0] == "capture" and not feedback.result_ready(), "Capture must decide the loss immediately and defer its result reveal.")
			check(is_same(feedback.defeat.source_enemy, enemy) and not is_same(feedback.defeat.carrier, enemy)
				and enemy.stolen_part == -1 and game.call("_defeated_source", enemy), "Defeat must use one visual carrier and no invented armor piece.")
			check(feedback.defeat.weapon == null and feedback.effects.filter(func(effect: Dictionary) -> bool: return effect.kind == "weapon").size() == 1,
				"The captured player must be unarmed and drop exactly one separate crossbow.")
			var original: Dictionary = enemy.duplicate(true)
			var elapsed: float = model.elapsed
			var initial: Vector2 = feedback.defeat.pos
			game.call("_toggle_pause")
			game.call("_physics_process", 0.5)
			check(feedback.defeat.age == 0 and feedback.defeat.pos == initial, "Pause must freeze the complete defeat sequence.")
			game.call("_toggle_pause")
			game.call("_physics_process", 0.5)
			check(feedback.defeat.pos != initial and feedback.defeat.carrier.pos.x != enemy.pos.x,
				"The thief must carry the player after the grab transfer.")
			check(enemy == original and model.elapsed == elapsed and model.result == "lose", "Defeat playback must not resume or mutate combat.")
			for frame in 100:
				game.call("_physics_process", 0.06)
				if feedback.result_ready():
					break
			check(feedback.result_ready() and absf(feedback.defeat.angle) > 1,
				"The carried player must turn sideways and leave the screen before the result reveal.")
			game.call("_restart")
			check(feedback.defeat.is_empty() and model.result == "", "Restart must discard all previous defeat references.")
	for furniture in [false, true]:
		for side in [-1.0, 1.0]:
			game.call("_restart")
			model.armor = 0
			model.hazards.append({"pos": model.player - Vector2(side * 10, 25), "velocity": Vector2(side * 80, model.config.nut_speed), "furniture": furniture})
			model._update_hazards(0.05)
			check(model.result == "lose" and feedback.defeat.kind == ("furniture" if furniture else "nut") and feedback.defeat.side == side,
				"Actual hazard hits must select a knockout toward the incoming travel direction.")
			var count: int = events.size()
			model.damage("second simultaneous hit")
			check(events.size() == count, "A decided defeat must not restart from another hit.")
			game.call("_physics_process", 0.3)
			check(feedback.defeat.angle != 0 and feedback.defeat.pos != feedback.defeat.origin and not feedback.result_ready(),
				"Knockout must fly and rotate before showing the panel.")
			for frame in 100:
				game.call("_physics_process", 0.06)
				if feedback.result_ready():
					break
			check(feedback.result_ready(), "Knockout must eventually leave the screen.")
	game.call("_restart")
	model.damage("armor hit")
	check(feedback.defeat.is_empty() and model.result == "", "Ordinary armor loss must not play a fatal defeat.")
	game.call("_restart")
	var enabled: bool = feedback.settings.defeat_enabled
	feedback.settings.defeat_enabled = false
	model.armor = 0
	model.damage("disabled knockout")
	check(model.result == "lose" and feedback.result_ready() and feedback.defeat.is_empty(), "Disabling defeat visuals must preserve the immediate game outcome.")
	feedback.settings.defeat_enabled = enabled
	for scenario in ["defeat_capture", "defeat_nut", "defeat_furniture"]:
		var index: int = game.get("scenario_ids").find(scenario)
		(game.get("scenario_picker") as OptionButton).select(index)
		game.call("_restart")
		for frame in 120:
			game.call("_physics_process", 1.0 / 60)
			if model.result != "":
				break
		check(model.result == "lose" and not feedback.defeat.is_empty(), "Each acceptance selector must trigger a real defeat through combat.")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("DEFEAT_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
