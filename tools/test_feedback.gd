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
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("FEEDBACK_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
