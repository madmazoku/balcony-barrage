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
	game.call("_shoot", direction)
	game.call("_update_hud")
	game.queue_redraw()
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(options.capture)
	if error != OK:
		push_error("Could not save QA capture.")
		quit(1)
		return
	print("CAPTURE_OK ", options.capture)
	quit()
