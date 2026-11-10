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
	model.balloon_popped.connect(func(position: Vector2, color: int, _source: Dictionary) -> void: pops.append([position, color]))
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
	_test_enemy_actions(game)
	var forest: Node = load("res://scenes/main.tscn").instantiate()
	forest.pack_override = load("res://assets/packs/forest_glade/pack.tres")
	root.add_child(forest)
	forest.set_physics_process(false)
	forest.scenario_picker.select(4)
	_test_enemy_actions(forest)
	_test_squirrel_poses(forest)
	_test_leaf_suspensions(forest)
	forest.queue_free()
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("FEEDBACK_TESTS_OK")
	quit(0 if failures.is_empty() else 1)

func _test_enemy_actions(game: Node) -> void:
	var model: RoundModel = game.get("model")
	var feedback: RoundFeedback = game.get("feedback")
	var throws: Array = []
	var captures: Array = []
	model.thrower_released.connect(func(enemy: Dictionary) -> void: throws.append(enemy))
	model.armor_stolen.connect(func(part: int, enemy: Dictionary) -> void:
		captures.append([part, enemy.state, enemy.pos, enemy.stolen_part]))
	game.call("_restart")
	model.spawn("thrower", Vector2(350, 300))
	var thrower: Dictionary = model.minions[0]
	thrower.windup = 0.05
	model._update_minions(0.04)
	check(throws.is_empty() and model.hazards.is_empty(), "A held nut must not become a projectile before release.")
	model._update_minions(0.02)
	check(throws.size() == 1 and model.hazards.size() == 1 and not feedback.enemy_effect(thrower, "release").is_empty(),
		"The actual throw must emit one release event and start the matching pose.")
	model._update_minions(0.02)
	check(throws.size() == 1, "Release animation must not create repeated projectiles.")
	game.call("_restart")
	model.spawn("thrower", Vector2(350, model.config.ground_y - model.config.thrower_size.y / 2 - 0.01))
	model.minions[0].windup = 0.001
	model._update_minions(0.1)
	check(throws.size() == 1 and model.hazards.is_empty(), "Landing must cancel an unfinished throw.")
	game.call("_restart")
	model.spawn("thrower", Vector2(350, 300))
	model.minions[0].windup = 0.001
	model.bolts.append({"pos": model.minions[0].pos, "velocity": Vector2.UP * model.config.bolt_speed})
	model._update_bolts(0.001)
	model._update_minions(0.1)
	check(throws.size() == 1 and model.hazards.is_empty(), "A defeated thrower must not release a queued nut.")
	for role in ["normal", "tank", "thrower"]:
		for side in [-1.0, 1.0]:
			for armor in [1, 2, 3]:
				game.call("_restart")
				model.armor = armor
				var offset: float = (model.body_size(role).x + model.config.player_size.x) / 2 - 1
				model.spawn(role, Vector2(model.player.x + side * offset, model.config.ground_y - model.body_size(role).y / 2))
				var thief: Dictionary = model.minions[0]
				thief.state = "ground"
				model._update_minions(0.001)
				var effect: Dictionary = feedback.enemy_effect(thief, "steal")
				check(not effect.is_empty() and effect.part == armor - 1 and captures.back()[1] == "escape"
					and captures.back()[2] == thief.pos and captures.back()[3] == armor - 1,
					"Capture event must see committed thief state and the exact armor piece.")
				check(feedback.effects.filter(func(e: Dictionary) -> bool: return e.kind == "armor").is_empty(),
					"A stolen piece must not also enter free flight.")
				var pose: Dictionary = game.call("_enemy_visual_pose", thief)
				check(pose.action == role + "_capture" and pose.flip == (side > 0), "Reach must face the player on both sides.")
				game.call("_toggle_pause")
				var before: Vector2 = thief.pos
				game.call("_physics_process", 0.1)
				check(effect.age == 0 and thief.pos == before, "Pause must freeze capture and its thief.")
				game.call("_toggle_pause")
				game.call("_physics_process", 0.1)
				check(effect.age > 0 and thief.pos != before, "Capture visuals must not delay the combat escape.")
				feedback.advance(feedback.settings.capture_seconds - effect.age - 0.00001)
				var handoff: Dictionary = game.call("_carried_armor_pose", thief)
				feedback.advance(0.00002)
				var carried: Dictionary = game.call("_carried_armor_pose", thief)
				check((handoff.pos as Vector2).distance_to(carried.pos) < 0.1 and feedback.effects.is_empty(),
					"The transfer must hand off to carried armor without a position jump or stale effects.")
	game.call("_restart")
	model.spawn("normal", model.player)
	model.minions[0].state = "ground"
	model._update_minions(0.001)
	check(not feedback.effects.is_empty(), "Actual scene must create capture feedback.")
	game.call("_restart")
	check(feedback.effects.is_empty(), "Restart must clear pending capture and release effects.")
	model.armor = 0
	model.spawn("normal", model.player)
	model.minions[0].state = "ground"
	var old_count: int = captures.size()
	model._update_minions(0.001)
	check(model.result == "lose" and captures.size() == old_count and feedback.effects.filter(func(effect: Dictionary) -> bool: return effect.kind in ["armor", "steal"]).is_empty(),
		"An unarmored capture must not create a transfer or invented item.")


func _test_squirrel_poses(game: Node) -> void:
	var pack: AssetPack = game.pack
	for variant in 3:
		var release: Texture2D = pack.enemy_action_frames["thrower_release"][variant]
		check(release == pack.enemy_action_frames["thrower_capture"][variant], "Squirrel capture must explicitly reuse its empty-handed release pose.")
		check(release.get_image().get_data() == (pack.run_frames["thrower_" + str(variant)][0] as Texture2D).get_image().get_data(),
			"After throwing, the squirrel must return to its original empty paws.")
		check((pack.enemy_action_frames["thrower_windup"][variant] as Texture2D).get_image().get_data() != release.get_image().get_data(),
			"The held walnut must visibly distinguish preparation from release.")
		var bag: Color = release.get_image().get_pixel(182, 350)
		check(bag.a > 0.95 and bag.g > bag.b, "The olive satchel must survive chroma-key removal in every palette.")
		for side in [-1.0, 1.0]:
			game._restart()
			game.model.player.x = 100 if side < 0 else 1100
			game.model.spawn("thrower", Vector2(640, 300))
			var enemy: Dictionary = game.model.minions[0]
			enemy.variant = variant
			enemy.windup = game.settings.nut_windup_seconds
			var pose: Dictionary = game._enemy_visual_pose(enemy)
			check(pose.action == "thrower_windup" and pose.flip == (side < 0), "Walnut preparation must face the target on both sides.")
			game._toggle_pause()
			game._physics_process(0.2)
			check(enemy.windup == game.settings.nut_windup_seconds and game.model.hazards.is_empty(), "Pause must freeze preparation without releasing a walnut.")
			game._toggle_pause()
			game.model._update_minions(game.settings.nut_windup_seconds + 0.001)
			check(game.model.hazards.size() == 1 and game._enemy_visual_pose(enemy).action == "thrower_release", "One actual throw must switch from held walnut to empty release pose.")
			var velocity: Vector2 = game.model.hazards[0].velocity
			check(absf(rad_to_deg(atan2(velocity.x, velocity.y))) <= game.settings.nut_max_angle_degrees + 0.001,
				"The original bounded downward attack angle must be preserved.")


func _test_leaf_suspensions(game: Node) -> void:
	var pack: AssetPack = game.pack
	check(pack.suspension_draw_size(game.settings.balloon_radius) == Vector2(32, 32), "Leaf proportions belong to the pack, not collision geometry.")
	var leaf_alpha: PackedByteArray
	for color in 4:
		var image: Image = pack.balloon_sprites[color].get_image()
		var alpha_image := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
		for y in image.get_height():
			for x in image.get_width():
				alpha_image.set_pixel(x, y, Color(image.get_pixel(x, y).a, 0, 0))
		if color == 0:
			leaf_alpha = alpha_image.get_data()
		else:
			check(alpha_image.get_data() == leaf_alpha, "Every leaf color must share the exact silhouette and petiole.")
		var anchor := Vector2i(pack.balloon_rope_anchor * Vector2(image.get_size()))
		check(anchor.y > image.get_height() * 0.9 and image.get_pixelv(anchor).a > 0.9,
			"Ropes must meet an opaque bottom petiole, not the center or transparent padding.")
		var frames: Array = pack.balloon_pop_frames[str(color)]
		check(frames.size() == 4, "Each leaf color needs a complete tear sequence.")
		for index in 4:
			var frame: Image = frames[index].get_image()
			check(frame.get_size() == Vector2i(128, 128) and not frame.is_invisible(), "Torn leaves must stay on their common nonempty canvas.")
			if index > 0:
				check(frame.get_data() != (frames[index - 1] as Texture2D).get_image().get_data(), "Leaf halves must visibly move between phases.")
	var events: Array = []
	game.model.balloon_popped.connect(func(position: Vector2, variant: int, _source: Dictionary) -> void: events.append([position, variant]))
	for role in ["normal", "thrower", "tank"]:
		for color in 4:
			game._restart()
			game.model.minions.clear()
			game.model.spawn(role, Vector2(450, 300))
			var enemy: Dictionary = game.model.minions[0]
			enemy.variant = color
			var connection: Vector2 = enemy.pos - Vector2(0, game.model.body_size(role).y / 2)
			for center in game.model.balloon_positions(enemy):
				var pose: Dictionary = pack.suspension_pose(center, connection, game.settings.balloon_radius)
				var stem: Vector2 = pose.anchor - center
				var cord: Vector2 = connection - pose.anchor
				check(absf(stem.cross(cord)) < 0.001 and stem.dot(cord) > 0,
					"Every leaf petiole and its cord must be collinear and point toward the owner.")
				check(absf(pose.angle) < PI / 2, "Leaves must fan outward without turning upside down.")
			var hp: int = enemy.hp
			var kills: int = game.model.kills
			for remaining in range(hp, 0, -1):
				var target: Vector2 = game.model.balloon_positions(enemy).back()
				var expected_angle: float = pack.suspension_pose(target, connection, game.settings.balloon_radius).angle
				var before: int = events.size()
				game.model.bolts.append({"pos": target + Vector2(0, 15), "velocity": Vector2.UP * game.settings.bolt_speed})
				game.model._update_bolts(0.05)
				check(enemy.hp == remaining - 1 and events.size() == before + 1 and events.back()[0] == target,
					"A real hit must remove exactly one leaf and emit one tear at its previous position.")
				var effect: Dictionary = game.feedback.effects.back()
				check(is_equal_approx(effect.angle, expected_angle), "A torn leaf must inherit its pre-hit tilt instead of snapping upright.")
				check(effect.kind == "pop" and effect.variant == (color + remaining - 1) % 4,
					"Torn fragments must use the removed leaf color.")
				if remaining == hp:
					game._toggle_pause()
					game._physics_process(0.2)
					check(effect.age == 0 and is_equal_approx(effect.angle, expected_angle), "Pause must freeze a leaf tear and its tilt.")
					game._toggle_pause()
			check(enemy.state == "fall" and game.model.kills == kills + 1, "Removing the last leaf must count one defeated minion.")
			game.feedback.advance(1.0)
			check(game.feedback.effects.is_empty(), "Expired leaf fragments must be removed.")
	game._restart()
	check(game.feedback.effects.is_empty(), "Restart must not leave leaf fragments from the previous round.")
