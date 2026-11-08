extends SceneTree
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func vertices(visual: RoundAmbient, id: String) -> PackedVector3Array:
	return visual.meshes[id].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var model: RoundModel = game.get("model")
	var visual: RoundAmbient = game.get("ambient")
	var pack: AssetPack = game.get("pack")
	check(visual != null and pack.validation_errors().is_empty(), "Ambient presentation must load as a complete pack.")
	var incomplete: AssetPack = pack.duplicate()
	incomplete.environment = pack.environment.duplicate()
	incomplete.environment.erase("ambient_" + visual.settings.layer_ids[0])
	check(not incomplete.validation_errors().is_empty(), "Missing foliage cannot fall back to another pack.")
	var bad: AmbientConfig = visual.settings.duplicate(true)
	bad.periods[bad.layer_ids[0]] = 0
	check(not bad.validation_errors().is_empty(), "A zero wind period must fail before play.")
	var initial: Dictionary = {}
	for id in visual.settings.layer_ids:
		var image: Image = (pack.environment["ambient_" + id] as Texture2D).get_image()
		check(not image.is_invisible() and image.detect_alpha() != Image.ALPHA_NONE, "Foliage needs visible generated pixels and alpha.")
		initial[id] = vertices(visual, id)
	visual.advance(0.7)
	for id in visual.settings.layer_ids:
		var before: PackedVector3Array = initial[id]
		var current: PackedVector3Array = vertices(visual, id)
		check(current != before, "Wind must move the generated leaf strip.")
		check(current[0] == before[0] and current[1] == before[1] and current[-1] == before[-1] and current[-2] == before[-2],
			"Both ends must stay anchored, including the stone cornice boundaries.")
		var area: Rect2 = visual.settings.layer_rects[id]
		var limit: Vector2 = visual.settings.amplitudes[id] * visual.arena / visual.settings.source_size
		for row in visual.settings.segments + 1:
			for column in 2:
				var rest: Vector2 = (area.position + Vector2(column, float(row) / visual.settings.segments) * area.size) * visual.arena
				var position: Vector3 = current[row * 2 + column]
				check(absf(position.x - rest.x) <= limit.x + 0.001 and absf(position.y - rest.y) <= limit.y + 0.001,
					"Wind displacement must remain bounded by pack settings.")
	visual.reset()
	visual.advance(12.0)
	for id in visual.settings.layer_ids:
		var before: PackedVector3Array = initial[id]
		var after: PackedVector3Array = vertices(visual, id)
		for index in before.size():
			check(before[index].distance_to(after[index]) < 0.001, "The full wind cycle must have no wrap seam.")
	game.call("_physics_process", 0.1)
	var phase: Dictionary = visual.phases.duplicate()
	game.call("_toggle_pause")
	game.call("_physics_process", 0.4)
	check(visual.phases == phase, "Pause must freeze the background.")
	game.call("_restart")
	check(visual.phases == visual.settings.phases, "Restart must reset every wind phase.")
	phase = visual.phases.duplicate()
	model.result = "lose"
	game.call("_physics_process", 0.2)
	check(visual.phases == phase, "Defeat must stop background presentation.")
	game.call("_restart")
	model.boss_falling = true
	phase = visual.phases.duplicate()
	game.call("_physics_process", 0.02)
	check(visual.phases == phase, "Decisive collapse must stop background presentation.")
	game.call("_restart")
	visual.settings = visual.settings.duplicate(true)
	visual.settings.enabled = false
	phase = visual.phases.duplicate()
	game.call("_physics_process", 0.3)
	check(visual.phases == phase, "Disabled ambient presentation must retain the static background.")
	visual.settings.enabled = true
	game.call("_restart")
	var baseline := RoundModel.new(model.config)
	model.grace = 1000
	baseline.grace = 1000
	for frame in 2200:
		if frame % 23 == 0:
			game.call("_shoot", Vector2.UP)
			baseline.shoot(Vector2.UP)
		game.call("_physics_process", 0.02)
		baseline.tick(0.02, 0)
	check(model.minions == baseline.minions and model.hazards == baseline.hazards and model.bolts == baseline.bolts
		and model.player == baseline.player and model.boss == baseline.boss and model.rng.state == baseline.rng.state
		and model.elapsed == baseline.elapsed and model.result == baseline.result and model.kills == baseline.kills
		and model.armor == baseline.armor, "Background animation must preserve combat, scoring, time and RNG.")
	for mesh in visual.meshes.values():
		check(mesh.get_surface_count() == 1, "Repeated wind updates must not accumulate mesh surfaces.")
	# Load the same real scene with an entire different pack, with no foliage resources.
	var presentation := load("res://config/presentation.tres") as PresentationConfig
	var original: AssetPack = presentation.active_pack
	presentation.active_pack = load("res://assets/packs/prototype/pack.tres")
	var prototype: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(prototype)
	prototype.set_physics_process(false)
	check(prototype.get("ambient") == null and prototype.get("model") != null, "A complete prototype pack needs no ambient resources.")
	presentation.active_pack = original
	prototype.queue_free()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("AMBIENT_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
