extends SceneTree
var failures: Array[String] = []
var app: GameShell

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func pad(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 67
		event.button_index = button
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func _run() -> void:
	var path := "user://qa-shell-%d.cfg" % OS.get_process_id()
	app = load("res://scenes/app.tscn").instantiate()
	app.profile_path = path
	root.add_child(app)
	await process_frame
	var game: Node = app.game
	var model: RoundModel = game.model
	check(app.mode == "home" and not game.is_physics_processing() and not game.controls.accepting_gameplay,
		"The actual entry scene must wait at the title screen.")
	for frame in 4: await physics_frame
	check(model.elapsed == 0 and model.released == 0, "The title screen must not spend time, spawn enemies or consume RNG.")
	check(app.first_button.has_focus(), "Keyboard and gamepad must have a focused Play button.")
	await key(KEY_ENTER)
	check(app.mode == "playing" and game.is_physics_processing() and model.bolts.is_empty(), "Menu acceptance must start exactly one round without a leaked shot.")
	await key(KEY_P)
	check(app.mode == "pause" and not game.controls.accepting_gameplay, "The real pause shortcut must open the pause menu.")
	var elapsed: float = model.elapsed
	for frame in 4: await physics_frame
	check(model.elapsed == elapsed, "Pause must freeze the actual round.")
	app.open_panel("settings")
	app.set_preference("show_hints", false)
	app.set_preference("background_motion", false)
	app.set_preference("touch_preview", true)
	check(not game.footer.visible and not game.ambient.settings.enabled and game.controls.touch_preview,
		"Preferences must apply to this presentation without changing the pack asset.")
	check(game.pack.ambient.enabled, "A user preference must not mutate the shared pack resource.")
	var reopened := GameProfile.new(path)
	check(not reopened.show_hints and not reopened.background_motion and reopened.touch_preview, "Real menu changes must persist.")
	await pad(JOY_BUTTON_B)
	check(app.mode == "pause", "Controller Back must return from settings to the paused round.")
	await pad(JOY_BUTTON_START)
	check(app.mode == "playing", "Controller Start must resume.")
	game.controls._focus_lost()
	check(app.mode == "pause", "Losing focus must open pause without later auto-resume.")
	app.resume_round()
	model.boss_falling = true
	app._request_pause()
	check(app.mode == "pause", "The accepted boss fall must remain pausable.")
	app.start_round()
	# A real final capture must finish its animation before the result menu.
	model.armor = 0
	model.minions.clear()
	model.spawn("normal", model.player)
	model.minions[0].state = "ground"
	model._update_minions(0.001)
	app._process(0)
	check(model.result == "lose" and app.mode == "playing", "The shell must not cover the accepted defeat animation early.")
	game.feedback.advance(game.feedback.settings.defeat_max_seconds + 1)
	app._process(0)
	check(app.mode == "result" and app.profile.best(game.settings).is_empty(), "Completed defeat must show results and preserve the victory record.")
	await key(KEY_R)
	check(app.mode == "playing" and model.result.is_empty() and model.kills == 0 and game.feedback.defeat.is_empty(), "Restart must clear both shell and accepted transient effects.")
	model.result = "win"
	model.kills = 7
	model.elapsed = 30
	app._process(0)
	check(app.mode == "result" and app.new_record and app.profile.best(game.settings).kills == 7, "A completed victory must display and save the record.")
	app.leave_round()
	check(app.mode == "home" and model.elapsed == 0 and not game.is_physics_processing(), "Returning home must discard the old session and stop it.")
	await process_frame
	await key(KEY_SPACE)
	check(app.mode == "playing" and model.bolts.is_empty(), "Using Space on Play must not fire a bolt into the new round.")
	app.leave_round()
	await process_frame
	await pad(JOY_BUTTON_DPAD_DOWN)
	check(not app.first_button.has_focus(), "Controller navigation must move focus between menu buttons.")
	await pad(JOY_BUTTON_DPAD_UP)
	check(app.first_button.has_focus(), "Controller navigation must return focus to Play.")
	await pad(JOY_BUTTON_A)
	check(app.mode == "playing" and model.bolts.is_empty(), "Controller Accept must start without a leaked shot.")
	app.leave_round()
	app.open_panel("help")
	await pad(JOY_BUTTON_DPAD_DOWN)
	check(app.help_label.text.contains("Стик"), "Help must follow the controller used in the menu.")
	await key(KEY_ESCAPE)
	check(app.mode == "home", "Escape must return from help.")
	app.queue_free()
	await process_frame
	var presentation := load("res://config/presentation.tres") as PresentationConfig
	var original: AssetPack = presentation.active_pack
	for pack_path in ["res://assets/packs/prototype/pack.tres", "res://assets/packs/prototype_alt/pack.tres"]:
		presentation.active_pack = load(pack_path)
		var other := load("res://scenes/app.tscn").instantiate() as GameShell
		other.profile_path = path
		root.add_child(other)
		check(other.mode == "home" and other.style == presentation.active_pack.ui["shell_style"],
			"Switching packs must select its own complete menu style.")
		other.queue_free()
		await process_frame
	presentation.active_pack = original
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	if failures.is_empty(): print("SHELL_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
