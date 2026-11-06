extends SceneTree
## Capture a reproducible real scene for sprite QA. Never exposed in game menus.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var options: Dictionary = {"scenario": "mixed", "pose": "right", "armor": "3", "stage": "0"}
	for argument in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	if not options.has("capture"):
		push_error("Pass -- --capture=<absolute PNG path>.")
		quit(1)
		return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	var model: RoundModel = game.get("model")
	var scenarios: Array = game.get("scenario_ids")
	var picker: OptionButton = game.get("scenario_picker")
	var selected: int = scenarios.find(options.scenario)
	if selected >= 0:
		picker.select(selected)
	game.call("_restart")
	model.armor = int(options.armor)
	model.broken_stages = int(options.stage)
	if options.has("fall-time"):
		model.broken_stages = model.config.balcony_stages - 1
		model.jump_remaining = 0.001
		model.tick(0.001, 0)
		model.tick(float(options["fall-time"]), 0)
	if options.get("result", "") == "win":
		model.boss.y = model.config.ground_y - model.config.boss_size.y / 2
	if options.get("result", "") in ["win", "lose"]:
		model.result = options.result
		model.cause = "Проверка финального экрана"
	var pose: String = options.pose
	var direction: Vector2 = Vector2.UP if pose == "up" else (Vector2.LEFT if pose == "left" else Vector2.RIGHT)
	var effect: String = options.get("feedback", "shot")
	match effect:
		"pop":
			model.minions.clear()
			model.spawn("thrower", Vector2(model.config.arena_size.x / 2, model.config.ground_y - 210))
			model.minions[0].variant = int(options.get("color", "0"))
			var balloon: Vector2 = model.balloon_positions(model.minions[0])[0]
			model.bolts.append({"pos": balloon + Vector2(0, 15), "velocity": Vector2.UP * model.config.bolt_speed})
			model._update_bolts(0.05)
			game.set("player_pose", pose)
		"armor":
			game.set("player_pose", pose)
			model.damage("Попадание гайкой")
		"capture":
			model.minions.clear()
			var role: String = options.get("role", "normal")
			var side: float = float(options.get("side", "1"))
			var offset: float = (model.body_size(role).x + model.config.player_size.x) / 2 - 1
			model.spawn(role, Vector2(model.player.x + side * offset, model.config.ground_y - model.body_size(role).y / 2))
			model.minions[0].state = "ground"
			model._update_minions(0.001)
		"windup":
			model.minions.clear()
			model.spawn("thrower", Vector2(model.config.arena_size.x / 2, model.config.ground_y - 210))
			model.minions[0].windup = model.config.nut_windup_seconds
			model.minions[0].variant = int(options.get("color", "0"))
		_:
			game.call("_shoot", direction)
	var feedback: RoundFeedback = game.get("feedback")
	if feedback != null:
		feedback.advance(float(options.get("feedback-time", "0")))
	game.call("_update_hud")
	var count: int = int(options.get("frames", "1"))
	for index in count:
		if index > 0 and feedback != null:
			if options.get("simulate", "false") == "true":
				game.call("_physics_process", float(options.get("step", "0.04")))
			else:
				feedback.advance(float(options.get("step", "0.04")))
		game.queue_redraw()
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = options.capture if count == 1 else options.capture.get_basename() + ("-%03d.png" % index)
		var image: Image = root.get_texture().get_image()
		var capture_size := Vector2i(int(ProjectSettings.get_setting("display/window/size/window_width_override")), int(ProjectSettings.get_setting("display/window/size/window_height_override")))
		if capture_size.x > 0 and capture_size.y > 0 and image.get_size() != capture_size:
			image.resize(capture_size.x, capture_size.y, Image.INTERPOLATE_LANCZOS)
		var error: Error = image.save_png(path)
		if error != OK:
			push_error("Could not save QA capture.")
			quit(1)
			return
	print("CAPTURE_OK ", options.capture, " frames=", count)
	quit()
