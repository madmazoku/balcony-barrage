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
	_check_platform_motion(pack)
	await process_frame
	if failures.is_empty(): print("BOSS_ACTION_TESTS_OK")
	quit(0 if failures.is_empty() else 1)

func _check_platform_motion(original: AssetPack) -> void:
	check(not original.environment.has("balcony_collapse_left"), "Original platform retains its existing artwork.")
	var forest := PackCatalog.new().load_pack("forest_glade")
	check(forest != null and forest.effects.has("platform_debris"), "Forest platform assets must load from the pack.")
	if forest == null:
		return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.set("pack_override", forest)
	root.add_child(game)
	game.set_physics_process(false)
	(game.get("scenario_picker") as OptionButton).select(4)
	game.call("_restart")
	var model: RoundModel = game.get("model")
	var platform: PlatformMotion = game.get("platform_motion")
	check(platform.settings == load("res://config/platform_motion.tres") and platform.settings.validation_errors().is_empty(),
		"Platform motion settings must come from the shared presentation config.")
	model.furniture_enabled = false
	for index in model.config.balcony_stages:
		platform.advance(platform.settings.debris_seconds)
		model.bolts.append({"pos": model.boss + Vector2(0, model.config.boss_size.y),
			"velocity": Vector2.UP * model.config.bolt_speed})
		model._update_bolts(0.2)
		check(platform.bursts.is_empty(), "A bolt must wait for the actual landing to shed debris.")
		game.call("_physics_process", model.config.boss_jump_seconds)
		check(platform.bursts.size() == 1 and platform.bursts[0].stage == index,
			"Every landing must shed the corresponding debris once.")
		check(platform.collapsed == (index == model.config.balcony_stages - 1), "The platform only folds on the last landing.")
		if index == 0:
			game.call("_physics_process", 0.08)
			var sag: float = platform.sag()
			check(sag > 0.0, "The platform must visibly give after a nonfinal impact.")
			game.call("_toggle_pause")
			game.call("_physics_process", 0.1)
			check(platform.sag() == sag, "Pause must freeze the platform and its debris.")
			game.call("_toggle_pause")
	check(model.boss_falling and model.result.is_empty(), "Boss falling starts on the same hit as the platform fold.")
	game.call("_physics_process", platform.settings.section_delay * 0.75)
	check(not is_zero_approx(platform.section_pose(platform.first_section).get_rotation())
		and is_zero_approx(platform.section_pose(1 - platform.first_section).get_rotation()),
		"The impacted section must fold before the other one follows.")
	game.call("_physics_process", platform.settings.hinge_seconds + platform.settings.section_delay + 0.03)
	check(platform.section_pose(0).origin.y > 0.0 and platform.section_pose(1).origin.y > 0.0,
		"Both platform sections must detach and descend.")
	game.call("_restart")
	check(not platform.collapsed and platform.age < 0.0 and platform.bursts.is_empty(),
		"Restart must clear the collapse and falling debris.")
	game.queue_free()
