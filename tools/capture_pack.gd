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
	var shell: GameShell
	var game: Node
	if options.has("shell"):
		shell = load("res://scenes/app.tscn").instantiate()
		shell.profile_path = "user://qa-capture-unused.cfg"
		root.add_child(shell)
		if options.has("pack"):
			if not shell.select_pack(options.pack):
				push_error("Unknown or incomplete capture pack: " + str(options.pack))
				quit(1)
				return
			shell._apply_selected_pack()
		shell.set_process(false)
		game = shell.game
	else:
		game = load("res://scenes/main.tscn").instantiate()
		if options.has("pack"):
			game.pack_override = PackCatalog.new().load_pack(options.pack)
			if game.pack_override == null:
				push_error("Unknown or incomplete capture pack: " + str(options.pack))
				game.free()
				quit(1)
				return
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
	game.set("player_pose", pose)
	match effect:
		"enemy":
			model.minions.clear()
			var role: String = options.get("role", "normal")
			var height: float = float(options.get("height", "200"))
			model.spawn(role, Vector2(model.config.arena_size.x / 2, model.config.ground_y - model.body_size(role).y / 2 - height))
			model.minions[0].state = options.get("state", "air")
			model.minions[0].variant = int(options.get("color", "0"))
			model.player.x = 80
		"ambient":
			model.minions.clear()
			model.furniture_enabled = false
		"boss_release":
			model.restart()
			model.released = 1
			model.elapsed = model.config.release_times[1] - 0.65
			model.player.x = 80
			model.grace = 1000
		"boss_throw":
			model.minions.clear()
			model.furniture_enabled = true
			model.furniture_windup = model.config.furniture_windup_seconds
			model.player.x = 80
		"boss_jump":
			model.minions.clear()
			model.furniture_enabled = false
			model.bolts.append({"pos": model.boss + Vector2(0, model.config.boss_size.y), "velocity": Vector2.UP * model.config.bolt_speed})
			model._update_bolts(0.2)
		"defeat":
			model.armor = 0
			model.minions.clear()
			model.hazards.clear()
			var cause: String = options.get("cause", "capture")
			var side: float = float(options.get("side", "1"))
			if cause == "capture":
				var role: String = options.get("role", "normal")
				var offset: float = (model.body_size(role).x + model.config.player_size.x) / 2 - 1
				model.spawn(role, Vector2(model.player.x + side * offset, model.config.ground_y - model.body_size(role).y / 2))
				model.minions[0].state = "ground"
				model.minions[0].variant = int(options.get("color", "0"))
				model._update_minions(0.001)
			else:
				model.hazards.append({"pos": model.player - Vector2(side * 10, 25), "velocity": Vector2(side * 80, model.config.nut_speed), "furniture": cause == "furniture"})
				model._update_hazards(0.05)
		"pop":
			model.minions.clear()
			model.spawn(options.get("role", "thrower"), Vector2(model.config.arena_size.x / 2, model.config.ground_y - 210))
			model.minions[0].variant = int(options.get("color", "0"))
			var balloon: Vector2 = model.balloon_positions(model.minions[0]).back()
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
		"run":
			model.minions.clear()
			var role: String = options.get("role", "player")
			var side: float = float(options.get("side", "1"))
			if role == "player":
				model.player.x = 300 if side > 0 else model.config.arena_size.x - 300
				var axis := InputEventJoypadMotion.new()
				axis.device = 91
				axis.axis = JOY_AXIS_LEFT_X
				axis.axis_value = side
				(game.get("controls") as PlayerControls)._input(axis)
			elif role == "boss":
				model.boss_direction = side
			else:
				model.player.x = 1100 if side > 0 else 180
				model.spawn(role, Vector2(400 if side > 0 else 880, model.config.ground_y - model.body_size(role).y / 2))
				model.minions[0].state = options.get("state", "ground")
				model.minions[0].escape_direction = side
				model.minions[0].variant = int(options.get("color", "0"))
				model.minions[0].stolen_part = int(options.get("part", "-1"))
			(game.get("motion") as RoundMotion).reset(model)
			game.set("player_pose", pose)
		"windup":
			model.minions.clear()
			model.spawn("thrower", Vector2(model.config.arena_size.x / 2, model.config.ground_y - 210))
			model.minions[0].windup = model.config.nut_windup_seconds
			model.minions[0].variant = int(options.get("color", "0"))
		_:
			game.call("_shoot", direction)
	if options.has("player-x"):
		model.player.x = float(options["player-x"])
	if effect.begins_with("boss_"):
		model.boss_direction = float(options.get("side", "1"))
	var feedback: RoundFeedback = game.get("feedback")
	if feedback != null:
		feedback.advance(float(options.get("feedback-time", "0")))
	game.call("_update_hud")
	if shell != null:
		if options.shell == "playing":
			shell.start_round()
			shell.game.set_physics_process(false)
		else:
			shell._show(options.shell)
	var count: int = int(options.get("frames", "1"))
	for index in count:
		if index > 0 and feedback != null:
			if options.get("simulate", "false") == "true":
				# Window focus may change while automated capture is stepping the scene.
				if game.get("paused"):
					game.call("_toggle_pause")
				game.call("_physics_process", float(options.get("step", "0.04")))
				if effect == "run" and options.get("role", "player") == "player" and pose == "up":
					game.call("_shoot", Vector2.UP)
			else:
				feedback.advance(float(options.get("step", "0.04")))
				if effect == "ambient" and game.get("ambient") != null:
					(game.get("ambient") as RoundAmbient).advance(float(options.get("step", "0.04")))
		game.queue_redraw()
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = options.capture if count == 1 else options.capture.get_basename() + ("-%03d.png" % index)
		var image: Image = root.get_texture().get_image()
		var capture_size := Vector2i(int(ProjectSettings.get_setting("display/window/size/window_width_override")), int(ProjectSettings.get_setting("display/window/size/window_height_override")))
		if capture_size.x > 0 and capture_size.y > 0 and image.get_size() != capture_size:
			image.resize(capture_size.x, capture_size.y, Image.INTERPOLATE_LANCZOS)
		if options.get("focus", "") == "actor":
			var role: String = options.get("role", "player")
			var position: Vector2 = model.player if role == "player" else (model.boss_draw_position() if role == "boss" else model.minions[0].pos)
			var ratio: Vector2 = Vector2(image.get_size()) / model.config.arena_size
			var left: int = clampi(int(position.x * ratio.x) - 90, 0, image.get_width() - 180)
			var top: int = int(position.y * ratio.y) - 65 if role == "boss" else int((model.config.ground_y - 50) * ratio.y) - 75
			if effect == "enemy" and options.get("state", "air") == "air":
				top = int(position.y * ratio.y) - 95
			image = image.get_region(Rect2i(left, top, 180, 130))
		var error: Error = image.save_png(path)
		if error != OK:
			push_error("Could not save QA capture.")
			quit(1)
			return
	print("CAPTURE_OK ", options.capture, " frames=", count)
	quit()
