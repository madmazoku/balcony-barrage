extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func axis(game: Node, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 91
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	(game.get("controls") as PlayerControls)._input(event)

func make_game(override: AssetPack = null) -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.pack_override = override
	root.add_child(game)
	game.set_physics_process(false)
	(game.get("scenario_picker") as OptionButton).select(4)
	game.call("_restart")
	return game

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = make_game()
	var model: RoundModel = game.get("model")
	var motion: RoundMotion = game.get("motion")
	var pack: AssetPack = game.get("pack")
	axis(game, 1)
	game.call("_physics_process", 0.15)
	check(motion.player_moving and is_equal_approx(motion.player_distance, model.config.player_speed * 0.15),
		"Running must measure actual player distance.")
	check(game.call("_player_frame") == pack.run_frames["player_right"][1], "Movement must select the generated stride on the real scene.")
	var phase: float = motion.player_distance
	var transform: Transform2D = game.call("_player_visual_transform")
	game.call("_toggle_pause")
	game.call("_physics_process", 0.2)
	check(motion.player_distance == phase and game.call("_player_visual_transform") == transform,
		"Pause must freeze the running frame and all attached layers.")
	game.call("_toggle_pause")
	game.call("_physics_process", 0.01)
	check(not motion.player_moving and motion.bob("player") == 0 and game.call("_player_frame") == pack.characters["player_right"],
		"Releasing movement must restore the neutral frame and stop the bounce.")
	model.player.x = model.config.arena_size.x - model.config.player_size.x / 2
	motion.reset(model)
	axis(game, 1)
	game.call("_physics_process", 0.15)
	check(not motion.player_moving and motion.player_distance == 0,
		"Holding movement against a clamped arena edge must not run in place.")
	for role in ["normal", "tank", "thrower"]:
		for side in [-1.0, 1.0]:
			for state in ["ground", "escape"]:
				game.call("_restart")
				model.player.x = 1100 if side > 0 else 180
				model.spawn(role, Vector2(400 if side > 0 else 880, model.config.ground_y - model.body_size(role).y / 2))
				var enemy: Dictionary = model.minions[0]
				enemy.state = state
				enemy.escape_direction = side
				motion.reset(model)
				game.call("_physics_process", 0.2)
				var pose: Dictionary = game.call("_enemy_visual_pose", enemy)
				check(pose.run_texture != null and pose.flip == (side < 0), "All grounded roles must run in both directions and during escape.")
				enemy.state = "fall"
				game.call("_physics_process", 0.01)
				pose = game.call("_enemy_visual_pose", enemy)
				check(pose.run_texture == null, "Falling enemies must stop using grounded running frames.")
				model.minions.clear()
				game.call("_physics_process", 0.01)
				check(motion.actors.is_empty(), "Removed enemies must not accumulate motion references.")
	game.call("_restart")
	axis(game, -1)
	game.call("_physics_process", 0.2)
	game.call("_restart")
	check(motion.player_distance == 0 and not motion.player_moving and motion.actors.is_empty(), "Restart must reset running state.")
	for side in [-1.0, 1.0]:
		game.call("_restart")
		model.boss_direction = side
		game.call("_physics_process", 0.2)
		check(motion.boss_moving and motion.frame_index("boss", pack.run_frames["boss_0"].size()) >= 0,
			"Boss movement in both directions must select a running frame.")
		model.jump_remaining = model.config.boss_jump_seconds
		game.call("_physics_process", 0.02)
		check(not motion.boss_moving and motion.frame_index("boss", 4) == -1, "Boss jump must suppress running.")
		model.boss_falling = true
		game.call("_physics_process", 0.02)
		check(not motion.boss_moving, "Final boss fall must suppress running.")
	game.call("_restart")
	# Two complete scenes replay the same combat with motion enabled/disabled.
	var other: Node = make_game()
	var other_model: RoundModel = other.get("model")
	var other_motion: RoundMotion = other.get("motion")
	other_motion.settings = motion.settings.duplicate()
	other_motion.settings.enabled = false
	model.restart()
	other_model.restart()
	motion.reset(model)
	other_motion.reset(other_model)
	for frame in 600:
		var direction: float = 1.0 if (frame / 80) % 2 == 0 else -1.0
		axis(game, direction)
		axis(other, direction)
		if frame % 23 == 0:
			game.call("_shoot", Vector2.UP)
			other.call("_shoot", Vector2.UP)
		game.call("_physics_process", 1.0 / 60)
		other.call("_physics_process", 1.0 / 60)
	check(model.player == other_model.player and model.minions == other_model.minions and model.hazards == other_model.hazards
		and model.bolts == other_model.bolts and model.armor == other_model.armor and model.kills == other_model.kills and model.result == other_model.result,
		"Running enabled or disabled must preserve the complete seeded combat outcome.")
	_check_forest_motion()
	_check_forest_enemy_motion("normal", 380)
	_check_forest_enemy_motion("thrower", 390)
	_check_forest_enemy_motion("tank", 350)
	game.queue_free()
	other.queue_free()
	await process_frame
	if failures.is_empty():
		print("MOTION_TESTS_OK")
	quit(0 if failures.is_empty() else 1)


func _check_forest_motion() -> void:
	var forest: AssetPack = load("res://assets/packs/forest_glade/pack.tres")
	check(forest.validation_errors().is_empty(), "The forest running pack must fulfill the full contract.")
	var game: Node = make_game(forest)
	for pose in ["right", "left", "up"]:
		var frames: Array = forest.run_frames["player_" + pose]
		check(frames.size() == 4, "Every aiming pose needs both alternating steps.")
		var neutral: Image = (forest.characters["player_" + pose] as Texture2D).get_image()
		var upper := Rect2i(0, 0, neutral.get_width(), 700)
		for frame in frames:
			check((frame as Texture2D).get_image().get_region(upper).get_data() == neutral.get_region(upper).get_data(),
				"Rabbit upper-body pixels changed in frame: " + str((frame as Texture2D).resource_path))
		check((frames[1] as Texture2D).get_image().get_data() != (frames[3] as Texture2D).get_image().get_data(),
			"Opposite steps cannot reuse the same neutral or lifted paw.")
		game._restart()
		axis(game, -1.0 if pose == "left" else 1.0)
		var seen: Dictionary = {}
		for index in 60:
			game._physics_process(0.02)
			if pose == "up" and game.model.cooldown <= 0:
				game._shoot(Vector2.UP)
			seen[game._player_frame().get_instance_id()] = true
		check(seen.size() == 3, "Actual movement/aiming must visit neutral and both steps.")
		var before: Texture2D = game._player_frame()
		var phase: float = game.motion.player_distance
		game._toggle_pause()
		game._physics_process(0.2)
		check(game._player_frame() == before and game.motion.player_distance == phase, "Pause must freeze the rabbit gait.")
		game._toggle_pause()
		game._physics_process(0.02)
		check(not game.motion.player_moving and game._player_frame() == forest.characters["player_" + pose],
			"Stopping must restore the matching accepted neutral aiming pose.")
	game.queue_free()


func _check_forest_enemy_motion(role: String, upper_rows: int) -> void:
	var forest: AssetPack = load("res://assets/packs/forest_glade/pack.tres")
	var game: Node = make_game(forest)
	for variant in 3:
		var frames: Array = forest.run_frames[role + "_" + str(variant)]
		var neutral: Image = (frames[0] as Texture2D).get_image()
		for frame in frames:
			check((frame as Texture2D).get_image().get_region(Rect2i(0, 0, 512, upper_rows)).get_data()
				== neutral.get_region(Rect2i(0, 0, 512, upper_rows)).get_data(), "The minion head and upper body must remain identical during its gait.")
		check((frames[1] as Texture2D).get_image().get_data() != (frames[3] as Texture2D).get_image().get_data(),
			"Every minion must alternate paws instead of duplicating a step.")
		for side in [-1.0, 1.0]:
			game._restart()
			game.model.player.x = 1100 if side > 0 else 180
			game.model.spawn(role, Vector2(600, game.settings.ground_y - game.model.body_size(role).y / 2))
			var enemy: Dictionary = game.model.minions[0]
			enemy.variant = variant
			enemy.state = "ground"
			game.motion.reset(game.model)
			var seen: Dictionary = {}
			for frame in 32:
				game._physics_process(0.025)
				var pose: Dictionary = game._enemy_visual_pose(enemy)
				check(pose.flip == (side < 0), "The running minion must face the player on both sides.")
				seen[pose.run_texture.get_instance_id()] = true
			check(seen.size() == 3, "Every minion palette must visit neutral and both actual steps.")
	game.queue_free()
