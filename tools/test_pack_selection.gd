extends SceneTree
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "user://qa-pack-selection-%d.cfg" % OS.get_process_id()
	var catalog := PackCatalog.new()
	check(catalog.errors.is_empty() and catalog.entries.size() == 2, "Both development packs must be explicitly installed.")
	check(catalog.resolve("missing") == catalog.default_id, "A removed pack preference must resolve to this build's own default.")
	var forest := catalog.load_pack("forest_glade")
	var original := catalog.load_pack("rescue_rangers")
	check(forest != null and forest.validation_errors().is_empty(), "Forest placeholder pack must fulfill every presentation slot.")
	check(forest.ui["shell_style"] != original.ui["shell_style"] and forest.ambient != original.ambient and forest.feedback != original.feedback and forest.locomotion != original.locomotion, "All configurations must be independent resources.")
	for image in [forest.characters["player"], forest.environment["background"], forest.effects["crossbow_right"], forest.run_frames["boss_0"][1]]:
		check(image.resource_path.begins_with("res://assets/packs/forest_glade/"), "Forest textures must come from its own directory.")
	var config: GameplayConfig = load("res://config/gameplay.tres")
	var rules := GameProfile.rules_key(config)
	var app := load("res://scenes/app.tscn").instantiate() as GameShell
	app.profile_path = path
	root.add_child(app)
	await process_frame
	app.start_round()
	app.game.model.tick(0.5, 1)
	app._request_pause()
	app.open_panel("settings")
	var old_game: Node = app.game
	var old_model: RoundModel = old_game.model
	var old_elapsed: float = old_model.elapsed
	check(app.pack_picker.item_count == 2, "Settings must list installed packs.")
	app.pack_picker.select(1)
	app.pack_picker.item_selected.emit(1)
	check(app.profile.selected_pack == "forest_glade" and app.active_pack_id == "rescue_rangers", "Menu choice must queue a whole-pack change for the next round.")
	check(app.game == old_game and old_model.elapsed == old_elapsed and app.game.paused, "Selecting a pack while paused must preserve the current model and pause state.")
	check(app.pack_preview.texture.resource_path.begins_with("res://assets/packs/forest_glade/"), "Preview must follow the pending selection.")
	check(app.status_label.text.contains("следующем"), "A deferred selection must be clearly explained.")
	check(GameProfile.new(path).selected_pack == "forest_glade", "Pack selection must survive reopening the profile.")
	check(not app.select_pack("unknown") and app.profile.selected_pack == "forest_glade", "An unknown choice cannot overwrite the saved preference.")
	app.close_panel()
	app.resume_round()
	check(app.game == old_game and old_model.elapsed == old_elapsed, "Resume must retain the old pack and round.")
	app.start_round()
	check(app.game != old_game and app.game.pack == forest and app.active_pack_id == "forest_glade", "Restart must install the entire selected pack.")
	check(app.style == forest.ui["shell_style"] and app.game.ambient.settings.resource_path != original.ambient.resource_path, "Menu and visual settings must travel with the selected pack.")
	check(app.game.model.elapsed == 0 and app.game.model.bolts.is_empty() and app.game.feedback.defeat.is_empty(), "New presentation starts with a clean round and no input/effect leak.")
	app.game.set_physics_process(false)
	# Replay identical inputs through real scene instances with different packs.
	var first: Node = load("res://scenes/main.tscn").instantiate()
	first.pack_override = original
	root.add_child(first)
	first.set_physics_process(false)
	for step in 240:
		var direction: float = 1 if step < 120 else -1
		if step % 30 == 0:
			first.model.shoot(Vector2.UP)
			app.game.model.shoot(Vector2.UP)
		first.model.tick(1.0 / 60, direction)
		app.game.model.tick(1.0 / 60, direction)
	check(first.model.player == app.game.model.player and first.model.minions == app.game.model.minions and first.model.hazards == app.game.model.hazards and first.model.kills == app.game.model.kills and first.model.armor == app.game.model.armor, "Pack selection must preserve deterministic combat and RNG.")
	first.queue_free()
	app.queue_free()
	await process_frame
	var reopened := load("res://scenes/app.tscn").instantiate() as GameShell
	reopened.profile_path = path
	root.add_child(reopened)
	await process_frame
	check(reopened.active_pack_id == "forest_glade" and reopened.mode == "home", "A fresh app instance must load the saved presentation before its title screen.")
	reopened.open_panel("settings")
	reopened.select_pack("rescue_rangers")
	reopened.close_panel()
	reopened.start_round()
	check(reopened.game.pack == original and reopened.active_pack_id == "rescue_rangers", "Switching back must restore the complete original pack.")
	check(GameProfile.rules_key(config) == rules, "Pack choices cannot modify gameplay or score identity.")
	reopened.queue_free()
	await process_frame
	var removed := GameProfile.new(path)
	removed.selected_pack = "removed_pack"
	removed.save_profile()
	var fallback := load("res://scenes/app.tscn").instantiate() as GameShell
	fallback.profile_path = path
	root.add_child(fallback)
	check(fallback.active_pack_id == catalog.default_id, "Missing saved content must start with the installed default, without loading a removed pack.")
	fallback.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty(): print("PACK_SELECTION_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
