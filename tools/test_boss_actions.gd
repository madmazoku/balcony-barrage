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
	var model: RoundModel = game.get("model")
	var visual: BossActions = game.get("boss_actions")
	var pack: AssetPack = game.get("pack")
	check(visual != null and pack.validation_errors().is_empty(), "Boss actions must load as a complete pack contract.")
	for frame in pack.boss_action_frames.values():
		var pixels: Image = (frame as Texture2D).get_image()
		check(not pixels.is_invisible() and pixels.detect_alpha() != Image.ALPHA_NONE, "Boss poses must contain visible generated artwork and transparent background.")
	var incomplete: AssetPack = pack.duplicate()
	incomplete.boss_action_frames = pack.boss_action_frames.duplicate()
	incomplete.boss_action_frames.erase("air")
	check(not incomplete.validation_errors().is_empty(), "Missing boss pose must be rejected without fallback.")
	var events: Array[String] = []
	model.boss_action.connect(func(kind: String) -> void: events.append(kind))
	game.call("_physics_process", 0.01)
	check(events == ["release"] and visual.pose(model).action == "release" and model.released == 1,
		"Only an actual scheduled spawn must trigger the release pose.")
	visual.clear()
	model.elapsed = model.config.release_times[model.released] - visual.settings.reach_seconds / 2
	check(visual.pose(model).action == "reach" and visual.pose(model).sack, "The hand must reach for the real upcoming release.")
	model.result = "lose"
	check(visual.pose(model).sack and visual.pose(model).action == "", "Early defeat must keep the remaining sack visible without continuing boss actions.")
	model.result = ""
	var age: float = visual.release_age
	game.call("_toggle_pause")
	game.call("_physics_process", 0.2)
	check(visual.release_age == age, "Pause must freeze boss presentation.")
	game.call("_toggle_pause")
	(game.get("scenario_picker") as OptionButton).select(4)
	game.call("_restart")
	check(visual.release_age == INF and visual.landing_age == INF, "Restart must discard boss action history.")
	model.furniture_windup = model.config.furniture_windup_seconds
	check(visual.pose(model).action == "hold" and visual.pose(model).furniture, "Real wind-up must hold the separate prop.")
	model.furniture_enabled = false
	check(not visual.pose(model).furniture, "Disabling furniture must hide a suspended wind-up.")
	model.furniture_enabled = true
	model.furniture_windup = 0.01
	game.call("_physics_process", 0.02)
	check(events.back() == "throw" and model.hazards.size() == 1 and visual.pose(model).action == "release" and not visual.pose(model).furniture,
		"Actual throw must remove the held prop and start follow-through exactly once.")
	model.hazards.clear()
	model.bolts.append({"pos": model.boss + Vector2(0, model.config.boss_size.y), "velocity": Vector2.UP * model.config.bolt_speed})
	model._update_bolts(0.2)
	check(model.jump_remaining > 0 and visual.pose(model).action == "air", "A real bolt hit must switch from running to airborne pose.")
	var stages: int = model.broken_stages
	game.call("_physics_process", model.config.boss_jump_seconds)
	check(model.broken_stages == stages + 1 and events.back() == "land" and visual.pose(model).action == "land",
		"A single landing pose must coincide with one actual balcony damage step.")
	model.jump_remaining = 0.01
	model.broken_stages = model.config.balcony_stages - 1
	game.call("_physics_process", 0.02)
	check(model.boss_falling and visual.pose(model).action == "air" and not visual.pose(model).furniture and not visual.pose(model).sack,
		"Final collapse must cancel all props and show falling before victory.")
	for frame in 100:
		game.call("_physics_process", 0.02)
		if model.result != "": break
	check(model.result == "win" and visual.pose(model).action == "", "Defeated seated art must remain reserved for landing on the ground.")
	# Presentation observes the same replay as a bare model and cannot alter RNG or damage.
	game.call("_restart")
	model.restart()
	visual.clear()
	var baseline := RoundModel.new(model.config)
	model.grace = 1000
	baseline.grace = 1000
	for frame in 2200:
		visual.advance(0.02)
		model.tick(0.02, 0)
		baseline.tick(0.02, 0)
		visual.pose(model)
	check(model.minions == baseline.minions and model.hazards == baseline.hazards and model.boss == baseline.boss
		and model.rng.state == baseline.rng.state and model.released == baseline.released and model.result == baseline.result
		and model.elapsed == baseline.elapsed, "Boss presentation must preserve the complete scheduled combat replay.")
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("BOSS_ACTION_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
