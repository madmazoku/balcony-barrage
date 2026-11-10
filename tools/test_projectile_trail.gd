extends SceneTree
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func scene(pack: AssetPack) -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.pack_override = pack
	root.add_child(game)
	game.set_physics_process(false)
	game.scenario_picker.select(4)
	game._restart()
	return game

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var forest: AssetPack = load("res://assets/packs/forest_glade/pack.tres")
	check(forest.validation_errors().is_empty(), "Forest projectile settings must be complete.")
	check((load("res://assets/packs/rescue_rangers/pack.tres") as AssetPack).projectile_visual == null,
		"The accepted original pack must retain its original rendering.")
	var invalid: ProjectileVisualConfig = forest.projectile_visual.duplicate()
	invalid.trail_samples = 1000
	check(not invalid.validation_errors().is_empty(), "Unbounded trail sampling must fail validation.")
	invalid = forest.projectile_visual.duplicate()
	invalid.glint_period = 0
	check(not invalid.validation_errors().is_empty(), "A zero glint period must fail validation.")
	invalid = forest.projectile_visual.duplicate()
	invalid.trail_length = INF
	check(not invalid.validation_errors().is_empty(), "Nonfinite visual geometry must fail validation.")
	var game: Node = scene(forest)
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP]:
		game._restart()
		game._shoot(direction)
		var bolt: Dictionary = game.model.bolts[0]
		var origin: Vector2 = bolt.pos
		var visual: ProjectileTrail = game.projectile_trail
		check(visual.pose(bolt, Vector2(12, 12)).trail.is_empty(), "A new shot cannot have a trail behind its muzzle.")
		game._shoot(-direction)
		check(visual.records.size() == 1 and game.model.bolts.size() == 1, "A cooldown-rejected shot must not create a visual projectile.")
		game._physics_process(0.04)
		var snapshot: Array = game.model.bolts.duplicate(true)
		var pose: Dictionary = visual.pose(bolt, Vector2(12, 12))
		check(pose.trail.size() == forest.projectile_visual.trail_samples, "A moving stone needs a bounded trail.")
		for sample in pose.trail:
			var position: Vector2 = bolt.pos - direction * float(sample.offset)
			check((position - origin).dot(direction) >= 0 and sample.tint.a > 0 and sample.tint.a < 1,
				"Every trail sample must lie behind its stone and after its muzzle in every direction.")
		check(game.model.bolts == snapshot, "Rendering must not modify the projectile dictionary.")
		var age: float = visual.records[0].age
		game._toggle_pause()
		game._physics_process(0.2)
		check(visual.records[0].age == age and game.model.bolts == snapshot, "Pause must freeze both trail and glint.")
		game._toggle_pause()
		game._physics_process(0.02)
		check(visual.records[0].age > age, "Resume must advance the visual clock.")
	# Consume the actual rightward shot on a ground enemy, then synchronize the visual state.
	game._restart()
	game._shoot(Vector2.RIGHT)
	game.model.spawn("normal", game.model.bolts[0].pos + Vector2(60, 0))
	game.model.minions[0].state = "ground"
	game._physics_process(0.1)
	check(game.model.bolts.is_empty() and game.projectile_trail.records.is_empty() and game.model.kills == 1,
		"An actual hit must remove its entire trail immediately and score only once.")
	game._restart()
	game._shoot(Vector2.UP)
	game._restart()
	check(game.projectile_trail.records.is_empty(), "Restart must release all old projectile references.")
	var disabled: AssetPack = forest.duplicate()
	disabled.projectile_visual = forest.projectile_visual.duplicate()
	disabled.projectile_visual.enabled = false
	var plain: Node = scene(disabled)
	game._restart()
	for frame in 360:
		var movement: float = sin(frame / 50.0)
		if frame % 29 == 0:
			game._shoot(Vector2.UP)
			plain._shoot(Vector2.UP)
		game.model.tick(1.0 / 60, movement)
		plain.model.tick(1.0 / 60, movement)
		game.projectile_trail.advance(game.model.bolts, 1.0 / 60)
		plain.projectile_trail.advance(plain.model.bolts, 1.0 / 60)
	check(game.model.bolts == plain.model.bolts and game.model.minions == plain.model.minions
		and game.model.hazards == plain.model.hazards and game.model.kills == plain.model.kills
		and game.model.armor == plain.model.armor and game.model.result == plain.model.result,
		"Enabling visual trails must leave seeded combat identical.")
	check(plain.projectile_trail.records.is_empty(), "Disabled effects cannot retain projectile state.")
	game.queue_free()
	plain.queue_free()
	await process_frame
	if failures.is_empty(): print("PROJECTILE_TRAIL_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
