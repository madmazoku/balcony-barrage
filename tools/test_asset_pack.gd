extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var presentation := load("res://config/presentation.tres") as PresentationConfig
	var original: AssetPack = presentation.active_pack
	var art := load("res://assets/packs/rescue_rangers/pack.tres") as AssetPack
	var prototype := load("res://assets/packs/prototype/pack.tres") as AssetPack
	check(art.validation_errors().is_empty(), "Static pack must be complete.")
	check(prototype.validation_errors().is_empty(), "Original prototype must remain loadable.")
	var incomplete: AssetPack = art.duplicate()
	incomplete.ui = art.ui.duplicate()
	incomplete.ui.erase("shell_style")
	check(not incomplete.validation_errors().is_empty(), "A pack cannot borrow another pack's menu style.")
	incomplete = art.duplicate()
	incomplete.characters = art.characters.duplicate()
	incomplete.characters.erase("player_up")
	check(not incomplete.validation_errors().is_empty(), "Missing pose must fail validation.")
	incomplete = art.duplicate()
	incomplete.balloon_sprites = art.balloon_sprites.duplicate()
	incomplete.balloon_sprites.remove_at(0)
	check(not incomplete.validation_errors().is_empty(), "Missing balloon variant must fail validation.")
	for category in [art.characters, art.effects]:
		for key in category:
			var texture := category[key] as Texture2D
			var image: Image = texture.get_image()
			check(image != null and not image.is_invisible(), "Empty sprite: " + key)
			if image != null:
				check(image.detect_alpha() != Image.ALPHA_NONE, "Foreground sprite must have alpha: " + key)
	if art.feedback != null:
		for frames in art.balloon_pop_frames.values():
			var frame_size: Vector2i = (frames[0] as Texture2D).get_image().get_size()
			for frame in frames:
				var image: Image = (frame as Texture2D).get_image()
				check(not image.is_invisible() and image.detect_alpha() != Image.ALPHA_NONE,
					"Pop frames must contain generated art and transparent background.")
				check(image.get_size() == frame_size, "Pop sequence must retain a fixed canvas.")
		var missing_pop: AssetPack = art.duplicate()
		missing_pop.balloon_pop_frames = art.balloon_pop_frames.duplicate()
		missing_pop.balloon_pop_frames.erase("0")
		check(not missing_pop.validation_errors().is_empty(), "A configured animation pack must include every color.")
	if art.feedback != null and art.feedback.enemy_actions_enabled:
		for frames in art.enemy_action_frames.values():
			for frame in frames:
				var image: Image = (frame as Texture2D).get_image()
				check(image.get_size() == Vector2i(512, 512) and not image.is_invisible() and image.detect_alpha() != Image.ALPHA_NONE,
					"Action poses require nonempty registered RGBA canvases.")
		var missing_action: AssetPack = art.duplicate()
		missing_action.enemy_action_frames = art.enemy_action_frames.duplicate()
		missing_action.enemy_action_frames.erase("tank_capture")
		check(not missing_action.validation_errors().is_empty(), "Configured actions cannot silently fall back to another pose or pack.")
		missing_action = art.duplicate()
		missing_action.enemy_frame_bounds = art.enemy_frame_bounds.duplicate()
		missing_action.enemy_frame_bounds["normal"] = Rect2(0, 0, 0, 1)
		check(not missing_action.validation_errors().is_empty(), "Missing alignment bounds must fail before play.")
	if art.locomotion != null:
		for key in art.run_frames:
			for frame in art.run_frames[key]:
				var image: Image = (frame as Texture2D).get_image()
				check(not image.is_invisible() and image.detect_alpha() != Image.ALPHA_NONE, "Running foreground must have usable alpha.")
		for pose in ["right", "left", "up"]:
			var neutral: Image = (art.characters["player_" + pose] as Texture2D).get_image()
			var upper := Rect2i(0, 0, neutral.get_width(), 700)
			for frame in art.run_frames["player_" + pose]:
				check((frame as Texture2D).get_image().get_region(upper).get_data() == neutral.get_region(upper).get_data(),
					"Running must preserve the exact player head, arms and equipment anchors.")
		var missing_run: AssetPack = art.duplicate()
		missing_run.run_frames = art.run_frames.duplicate()
		missing_run.run_frames.erase("player_left")
		check(not missing_run.validation_errors().is_empty(), "Missing running pose must fail validation.")
	for role in ["normal", "tank", "thrower"]:
		check(art.character_variants[role].size() == 3, "Each minion role needs three palettes.")
	check((art.environment["balcony_5"] as Texture2D).get_image().is_invisible(),
		"Final balcony state must be fully collapsed.")
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/build-static-pack.json"))["balcony_preparation"]
	var intact: Image = (art.environment["balcony_0"] as Texture2D).get_image()
	var deck := Rect2i(0, 0, intact.get_width(), int(recipe.preserved_deck_rows))
	var previous: Image = intact
	for stage in range(1, 5):
		var damaged: Image = (art.environment["balcony_" + str(stage)] as Texture2D).get_image()
		check(damaged.get_size() == intact.get_size(), "Balcony states must share a fixed frame.")
		check(damaged.get_region(deck).get_data() == intact.get_region(deck).get_data(),
			"Intermediate damage must preserve the original continuous walking deck.")
		check(damaged.get_data() != previous.get_data(), "Each damage stage must change visibly.")
		previous = damaged
	check(art.characters["boss_defeated"] != art.characters["boss"],
		"Victory must use a separate defeated boss sprite.")
	# Use the actual entry scene with both complete packs, while replaying identical combat inputs.
	presentation.active_pack = prototype
	var first: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(first)
	first.set_physics_process(false)
	presentation.active_pack = art
	var second: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(second)
	second.set_physics_process(false)
	var first_model: RoundModel = first.get("model")
	var second_model: RoundModel = second.get("model")
	check(first.get("pack") == prototype and second.get("pack") == art, "One active-pack reference must select the entire presentation.")
	first_model.restart()
	second_model.restart()
	for frame in 480:
		var movement: float = sin(frame / 80.0)
		if frame % 29 == 0:
			first.call("_shoot", Vector2.UP)
			second.call("_shoot", Vector2.UP)
		first_model.tick(1.0 / 60, movement)
		second_model.tick(1.0 / 60, movement)
	check(first_model.minions == second_model.minions and first_model.hazards == second_model.hazards
		and first_model.kills == second_model.kills and first_model.armor == second_model.armor,
		"Changing presentation must preserve seeded gameplay.")
	presentation.active_pack = original
	first.queue_free()
	second.queue_free()
	await process_frame
	if failures.is_empty():
		print("ASSET_PACK_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
