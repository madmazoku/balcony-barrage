extends Node2D

var settings: GameplayConfig = preload("res://config/gameplay.tres")
var presentation: PresentationConfig = preload("res://config/presentation.tres")
var pack: AssetPack
var model: RoundModel
var paused: bool = false
var hud: Label
var footer: Label
var scenario_picker: OptionButton
var furniture_check: CheckButton
var scenario_ids: Array[String] = ["round", "line", "landing", "damage", "boss", "mixed"]
var font: Font = ThemeDB.fallback_font
var controls: PlayerControls
var player_pose: String = "right"
var feedback: RoundFeedback

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pack = presentation.active_pack
	if pack == null:
		push_error("No active presentation pack.")
		set_physics_process(false)
		return
	var failures: Array[String] = pack.validation_errors()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		set_physics_process(false)
		return
	model = RoundModel.new(settings)
	if pack.feedback != null:
		feedback = RoundFeedback.new(pack.feedback)
		model.balloon_popped.connect(_on_balloon_popped)
		model.armor_removed.connect(_on_armor_removed)
		model.thrower_released.connect(_on_thrower_released)
		model.armor_stolen.connect(_on_armor_stolen)
	controls = PlayerControls.new()
	controls.gameplay = settings
	controls.player_x = model.player.x
	controls.shot_requested.connect(_shoot)
	controls.pause_requested.connect(_toggle_pause)
	controls.restart_requested.connect(_restart)
	add_child(controls)
	_create_controls()
	queue_redraw()

func _create_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(22, 12)
	panel.modulate = pack.colors["text"]
	layer.add_child(panel)
	var title := Label.new()
	title.text = "BALCONY BARRAGE"
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 14)
	panel.add_child(toolbar)
	scenario_picker = OptionButton.new()
	for label in ["Полный раунд", "Две цели на линии", "Последний шарик у земли", "Захват + гайка", "Пустой мешок / босс", "Три типа вместе"]:
		scenario_picker.add_item(label)
	scenario_picker.item_selected.connect(func(_index: int) -> void: _restart())
	toolbar.add_child(scenario_picker)
	var restart := Button.new()
	restart.text = "Заново [R]"
	restart.pressed.connect(_restart)
	toolbar.add_child(restart)
	furniture_check = CheckButton.new()
	furniture_check.text = "Мебель в финале"
	furniture_check.button_pressed = settings.furniture_enabled
	furniture_check.toggled.connect(func(enabled: bool) -> void:
		model.furniture_enabled = enabled)
	toolbar.add_child(furniture_check)
	var pause_button := Button.new()
	pause_button.text = "Пауза [P]"
	pause_button.pressed.connect(_toggle_pause)
	toolbar.add_child(pause_button)
	var touch_test := CheckButton.new()
	touch_test.text = "Тач мышью"
	touch_test.visible = not OS.has_feature("mobile")
	touch_test.toggled.connect(func(enabled: bool) -> void:
		self.controls.clear()
		self.controls.touch_preview = enabled
		self.controls.last_device = "touch" if enabled else "keyboard")
	toolbar.add_child(touch_test)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 18)
	panel.add_child(hud)
	footer = Label.new()
	footer.modulate = pack.colors["text"]
	footer.position = Vector2(22, settings.ground_y + 10)
	footer.add_theme_font_size_override("font_size", 17)
	layer.add_child(footer)
	# Keyboard focus stays with the game after clicking a prototype control.
	for control in toolbar.get_children():
		control.focus_mode = Control.FOCUS_NONE
	_update_hud()

func _restart() -> void:
	var enabled: bool = furniture_check.button_pressed
	model.restart(scenario_ids[scenario_picker.selected])
	model.furniture_enabled = enabled
	paused = false
	controls.clear()
	controls.accepting_gameplay = true
	controls.player_x = model.player.x
	player_pose = "right"
	if feedback != null:
		feedback.clear()
	queue_redraw()

func _shoot(direction: Vector2) -> void:
	if not paused and model.shoot(direction):
		player_pose = "up" if direction.y < 0 else ("left" if direction.x < 0 else "right")
		if feedback != null:
			feedback.shoot(direction)

func _on_balloon_popped(position: Vector2, color_variant: int) -> void:
	var index: int = color_variant % pack.balloon_sprites.size()
	feedback.pop(position, index, pack.balloon_pop_frames[str(index)].size())

func _player_visual_transform() -> Transform2D:
	var foot := Vector2(model.player.x, model.player.y + settings.player_size.y / 2)
	if feedback == null:
		return Transform2D(0, foot)
	var weight: float = feedback.recoil_weight()
	var angle: float = -feedback.shot_direction.x * deg_to_rad(feedback.settings.shot_tilt_degrees) * weight
	return Transform2D(angle, Vector2(1, 1 - feedback.settings.shot_squash * weight), 0, foot)

func _armor_visual_origin(part: int) -> Dictionary:
	var layer := pack.characters["armor_%d_%s" % [part, player_pose]] as Texture2D
	var bounds: Rect2i = layer.get_image().get_used_rect()
	var scale_factor: float = settings.player_size.y / pack.player_body_height
	var origin: Vector2 = _player_visual_transform() * ((Vector2(bounds.position) + Vector2(bounds.size) / 2 - pack.player_anchor) * scale_factor)
	return {"pos": origin, "size": Vector2(bounds.size) * scale_factor}

func _on_armor_removed(part: int, stolen: bool) -> void:
	if stolen or part >= 3:
		return
	var piece: Dictionary = _armor_visual_origin(part)
	feedback.armor(piece.pos, piece.size, part)

func _on_thrower_released(enemy: Dictionary) -> void:
	feedback.release(enemy)

func _on_armor_stolen(part: int, thief: Dictionary) -> void:
	if part >= 3:
		return
	var piece: Dictionary = _armor_visual_origin(part)
	feedback.steal(piece.pos, piece.size, part, thief)

func _enemy_actions_active() -> bool:
	return feedback != null and feedback.settings.enabled and feedback.settings.enemy_actions_enabled

func _enemy_visual_pose(enemy: Dictionary) -> Dictionary:
	var pose: Dictionary = {"pos": enemy.pos, "flip": enemy.escape_direction < 0 if enemy.state == "escape" else enemy.pos.x > model.player.x,
		"action": "", "angle": 0.0}
	if not _enemy_actions_active():
		return pose
	if enemy.state == "air" and enemy.role == "thrower":
		var weight: float = 0.0
		if enemy.windup > 0:
			pose.action = "thrower_windup"
			weight = clampf(1.0 - enemy.windup / settings.nut_windup_seconds, 0, 1)
		else:
			var release: Dictionary = feedback.enemy_effect(enemy, "release")
			if not release.is_empty():
				pose.action = "thrower_release"
				weight = 1.0 - release.age / release.lifetime
		pose.angle = deg_to_rad(feedback.settings.windup_tilt_degrees) * weight * (1 if pose.flip else -1)
	if enemy.state == "escape":
		var steal: Dictionary = feedback.enemy_effect(enemy, "steal")
		if not steal.is_empty():
			var phase: float = steal.age / steal.lifetime
			var reach: float = feedback.settings.capture_reach_fraction
			if phase < reach:
				pose.pos = steal.start_pos
				pose.flip = enemy.escape_direction > 0
				pose.action = enemy.role + "_capture"
			else:
				pose.pos = (steal.start_pos as Vector2).lerp(enemy.pos, smoothstep(reach, 1, phase))
			pose.angle = deg_to_rad(feedback.settings.capture_tilt_degrees) * sin(PI * phase) * enemy.escape_direction
	return pose

func _carried_armor_pose(enemy: Dictionary) -> Dictionary:
	if not _enemy_actions_active():
		return {"pos": enemy.pos + Vector2(15, 0), "size": Vector2(15, 16)}
	var pose: Dictionary = _enemy_visual_pose(enemy)
	var side: float = enemy.escape_direction
	var steal: Dictionary = feedback.enemy_effect(enemy, "steal")
	if not steal.is_empty():
		var phase: float = steal.age / steal.lifetime
		side = lerpf(-side, side, smoothstep(feedback.settings.capture_reach_fraction, 1, phase))
	return {"pos": pose.pos + feedback.settings.carry_offset * Vector2(side, 1), "size": feedback.settings.carry_size}

func _draw_enemy(enemy: Dictionary) -> void:
	var pose: Dictionary = _enemy_visual_pose(enemy)
	var size: Vector2 = model.body_size(enemy.role)
	if pose.action == "":
		_sprite_body(pose.pos, size, enemy.role, enemy.variant, pose.flip)
		return
	var options: Array = pack.enemy_action_frames[pose.action]
	var texture := options[int(enemy.variant) % options.size()] as Texture2D
	var reference: Rect2 = pack.enemy_frame_bounds[enemy.role]
	var scale_factor: Vector2 = size / (texture.get_size() * reference.size)
	var frame := Rect2(-reference.get_center() * texture.get_size() * scale_factor, texture.get_size() * scale_factor)
	draw_set_transform(pose.pos, pose.angle, Vector2(-1, 1) if pose.flip else Vector2.ONE)
	draw_texture_rect(texture, frame, false)
	draw_set_transform(Vector2.ZERO)

func _draw_feedback() -> void:
	if feedback == null:
		return
	for effect in feedback.effects:
		if effect.kind == "pop":
			var frames: Array = pack.balloon_pop_frames[str(effect.variant)]
			var index: int = mini(frames.size() - 1, int(effect.age / feedback.settings.pop_frame_seconds))
			var size: float = settings.balloon_radius * 2.6 * feedback.settings.pop_size_multiplier
			_texture_center(frames[index] as Texture2D, effect.pos, Vector2.ONE * size)
		elif effect.kind == "armor":
			draw_set_transform(effect.pos, effect.angle)
			draw_texture_rect(pack.effects["armor_" + str(effect.part)] as Texture2D, Rect2(-effect.size / 2, effect.size), false)
			draw_set_transform(Vector2.ZERO)
		elif effect.kind == "steal":
			var target: Dictionary = _carried_armor_pose(effect.enemy)
			var progress: float = smoothstep(0, feedback.settings.armor_transfer_seconds, effect.age)
			_texture_center(pack.effects["armor_" + str(effect.part)] as Texture2D,
				(effect.pos as Vector2).lerp(target.pos, progress), (effect.size as Vector2).lerp(target.size, progress))

func _toggle_pause() -> void:
	paused = not paused
	controls.accepting_gameplay = not paused
	controls.clear()

func _physics_process(delta: float) -> void:
	if model == null:
		return
	if not paused:
		if feedback != null:
			feedback.advance(delta)
		var movement: float = controls.movement(model.player.x, delta)
		model.tick(delta, movement)
		if model.cooldown <= 0 and not is_zero_approx(movement):
			player_pose = "left" if movement < 0 else "right"
	controls.player_x = model.player.x
	_update_hud()
	queue_redraw()

func _update_hud() -> void:
	hud.text = "Броня %d  ·  Мешок %d  ·  Балкон %d/%d  ·  Сбито %d  ·  %.1f c  ·  %.1f / мин" % [
		model.armor, settings.release_roles.size() - model.released,
		settings.balcony_stages - model.broken_stages, settings.balcony_stages,
		model.kills, model.elapsed, model.rate()]
	match controls.last_device:
		"gamepad":
			footer.text = "Стик / крестовина — бег    A / × — выстрел    Y / △ — повтор    Start — пауза"
		"touch":
			footer.text = "Тяни — движение    Тап выше наземной полосы — вверх    Тап в полосе — вбок"
		_:
			footer.text = "A/D или стрелки — бег    Пробел — вверх; с направлением — вбок    R — повтор    P — пауза"
	footer.text += "\n" + ("ПАУЗА" if paused else model.last_event)

func _text(position: Vector2, text: String, size: int = 17) -> void:
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, pack.colors["text"])

func _body(position: Vector2, size: Vector2, role: String) -> void:
	var color: Color = pack.colors[role]
	draw_rect(Rect2(position - size / 2, size), color)
	draw_rect(Rect2(position - size / 2, size), pack.colors["text"], false, 1.5)
	_text(position + Vector2(-size.x / 2, -size.y / 2 - 7), pack.display_names[role], 15)

func _draw() -> void:
	if model == null:
		return
	if pack.readiness == "static":
		_draw_static()
		_draw_result()
		return
	draw_rect(Rect2(Vector2.ZERO, settings.arena_size), pack.colors["background"])
	draw_rect(Rect2(0, settings.ground_y, settings.arena_size.x, settings.arena_size.y - settings.ground_y), pack.colors["ground"])
	if controls.last_device == "touch" or controls.touch_preview:
		var boundary: float = settings.ground_y - controls.settings.ground_tap_height
		var band_color: Color = pack.colors["ground"]
		band_color.a = 0.16
		draw_rect(Rect2(0, boundary, settings.arena_size.x, settings.ground_y - boundary), band_color)
		draw_line(Vector2(0, boundary), Vector2(settings.arena_size.x, boundary), pack.colors["ground"])
	var segment_width: float = (settings.balcony_right - settings.balcony_left) / settings.balcony_stages
	for stage in settings.balcony_stages:
		var color: Color = pack.colors["balcony"]
		if stage < model.broken_stages:
			color.a = 0.2
		draw_rect(Rect2(settings.balcony_left + stage * segment_width, settings.balcony_y, segment_width - 5, 18), color)
	_text(Vector2(settings.balcony_left, settings.balcony_y + 48),
		"Мешок пуст — попади в босса" if model.released >= settings.release_roles.size() else "Босс защищён, пока мешок не опустел")
	var boss_position: Vector2 = model.boss_draw_position()
	_body(boss_position, settings.boss_size, "boss")
	if model.furniture_windup > 0:
		draw_rect(Rect2(boss_position - Vector2(settings.furniture_hit_width / 2, settings.boss_size.y),
			Vector2(settings.furniture_hit_width, settings.furniture_height)), pack.colors["furniture"])
		_text(boss_position + Vector2(65, -10), "БРОСОК!")
	var player_color: Color = pack.colors["player"]
	if model.grace > 0:
		player_color.a = 0.45
	draw_rect(Rect2(model.player - settings.player_size / 2, settings.player_size), player_color)
	_text(model.player - settings.player_size / 2 - Vector2(0, 10), pack.display_names["player"])
	for part in model.armor:
		draw_rect(Rect2(model.player + Vector2(-22 + part * 15, -10), Vector2(12, 20)), pack.colors["armor"])
	for enemy in model.minions:
		_body(enemy.pos, model.body_size(enemy.role), enemy.role)
		# Same hash selects colors without consuming simulation randomness.
		if enemy.state == "air":
			var positions: Array[Vector2] = model.balloon_positions(enemy)
			for index in positions.size():
				var balloon: Vector2 = positions[index]
				var palette_index: int = (int(enemy.variant) + index) % pack.balloon_palette.size()
				draw_line(enemy.pos, balloon + Vector2(0, settings.balloon_radius), pack.colors["text"], 1.0)
				draw_circle(balloon, settings.balloon_radius, pack.balloon_palette[palette_index])
			if enemy.windup > 0:
				_text(enemy.pos + Vector2(28, 4), "ГАЙКА!")
		elif enemy.state == "escape":
			draw_rect(Rect2(enemy.pos + Vector2(20, 0), Vector2(12, 20)), pack.colors["armor"])
			_text(enemy.pos + Vector2(-25, 45), "УНОСИТ")
	for bolt in model.bolts:
		var horizontal: bool = bolt.velocity.x != 0
		var size: Vector2 = Vector2(settings.bolt_size.y, settings.bolt_size.x) if horizontal else settings.bolt_size
		draw_rect(Rect2(bolt.pos - size / 2, size), pack.colors["bolt"])
	for hazard in model.hazards:
		var size: Vector2 = Vector2(settings.furniture_hit_width, settings.furniture_height) if hazard.furniture else settings.nut_size
		draw_rect(Rect2(hazard.pos - size / 2, size), pack.colors["furniture" if hazard.furniture else "nut"])
	_draw_result()

func _draw_result() -> void:
	if model.result != "":
		draw_rect(Rect2(300, 350, 680, 180), pack.colors.get("result_panel", Color(0.04, 0.06, 0.09, 0.96)))
		_text(Vector2(340, 395), "ПОБЕДА — балкон рухнул!" if model.result == "win" else "ПОРАЖЕНИЕ — " + model.cause, 26)
		_text(Vector2(340, 437), "Сбито %d  /  %.1f сек  /  %.1f в минуту" % [model.kills, model.elapsed, model.rate()], 22)
		_text(Vector2(340, 485), "R — попробовать снова", 22)

func _texture_center(texture: Texture2D, position: Vector2, size: Vector2, flip: bool = false) -> void:
	draw_set_transform(position, 0, Vector2(-1, 1) if flip else Vector2.ONE)
	draw_texture_rect(texture, Rect2(-size / 2, size), false)
	draw_set_transform(Vector2.ZERO)

func _sprite_body(position: Vector2, size: Vector2, role: String, variant: int = 0, flip: bool = false) -> void:
	var texture := pack.characters[role] as Texture2D
	if pack.character_variants.has(role):
		var options: Array = pack.character_variants[role]
		texture = options[variant % options.size()] as Texture2D
	_texture_center(texture, position, size, flip)
	if pack.show_names:
		_text(position - size / 2 - Vector2(0, 7), pack.display_names[role], 15)

func _draw_static() -> void:
	draw_texture_rect(pack.environment["background"] as Texture2D,
		Rect2(Vector2.ZERO, settings.arena_size), false)
	draw_texture_rect(pack.environment["ground"] as Texture2D,
		Rect2(0, settings.ground_y, settings.arena_size.x, settings.arena_size.y - settings.ground_y), false)
	# Five authored visual states interpolate across configurable boss health.
	var stage: int = mini(5, int(ceil(float(model.broken_stages) / settings.balcony_stages * 5)))
	draw_texture_rect(pack.environment["balcony_" + str(stage)] as Texture2D,
		Rect2(settings.balcony_left, settings.balcony_y,
			settings.balcony_right - settings.balcony_left, pack.balcony_draw_height), false)
	var boss_position: Vector2 = model.boss_draw_position()
	_sprite_body(boss_position, settings.boss_size, "boss_defeated" if model.result == "win" else "boss", 0, model.boss_direction < 0)
	if model.released < settings.release_roles.size():
		_texture_center(pack.effects["sack"] as Texture2D,
			boss_position + settings.boss_size * Vector2(.15, .15), settings.boss_size * Vector2(.42, .60))
	if model.furniture_windup > 0:
		_texture_center(pack.effects["furniture"] as Texture2D,
			boss_position + settings.boss_size * Vector2(.6, -.3),
			Vector2(settings.furniture_hit_width, settings.furniture_height))
		_text(boss_position + Vector2(60, -35), "БРОСОК!")
	var frame := pack.characters["player_" + player_pose] as Texture2D
	var scale_factor: float = settings.player_size.y / pack.player_body_height
	var frame_rect := Rect2(-pack.player_anchor * scale_factor, frame.get_size() * scale_factor)
	draw_set_transform_matrix(_player_visual_transform())
	var tint := Color(1, 1, 1, .45 if model.grace > 0 else 1.0)
	draw_texture_rect(frame, frame_rect, false, tint)
	draw_texture_rect(pack.effects["crossbow_" + player_pose] as Texture2D, frame_rect, false, tint)
	for part in mini(model.armor, 3):
		draw_texture_rect(pack.characters["armor_%d_%s" % [part, player_pose]] as Texture2D, frame_rect, false, tint)
	draw_set_transform(Vector2.ZERO)
	for enemy in model.minions:
		if enemy.state == "air":
			var positions: Array[Vector2] = model.balloon_positions(enemy)
			for index in positions.size():
				var balloon: Vector2 = positions[index]
				var balloon_size := Vector2(settings.balloon_radius * 2, settings.balloon_radius * 2.6)
				var knot: Vector2 = balloon + (pack.balloon_rope_anchor - Vector2(0.5, 0.5)) * balloon_size
				var connection: Vector2 = enemy.pos - Vector2(0, model.body_size(enemy.role).y / 2)
				var rope: Vector2 = connection - knot
				draw_set_transform(knot, rope.angle() - PI / 2)
				draw_texture_rect(pack.effects["rope"] as Texture2D, Rect2(-.75, 0, 1.5, rope.length()), false)
				draw_set_transform(Vector2.ZERO)
				var color_index: int = (int(enemy.variant) + index) % pack.balloon_sprites.size()
				_texture_center(pack.balloon_sprites[color_index], balloon, balloon_size)
		_draw_enemy(enemy)
		if enemy.windup > 0 and not _enemy_actions_active():
			_texture_center(pack.effects["nut"] as Texture2D,
				enemy.pos + Vector2(-model.body_size(enemy.role).x / 2, -model.body_size(enemy.role).y / 2), settings.nut_size)
		if enemy.state == "escape" and enemy.stolen_part >= 0 and enemy.stolen_part < 3:
			var transferring: bool = _enemy_actions_active() and not feedback.enemy_effect(enemy, "steal").is_empty()
			if not transferring:
				var carried: Dictionary = _carried_armor_pose(enemy)
				_texture_center(pack.effects["armor_" + str(enemy.stolen_part)] as Texture2D, carried.pos, carried.size)
	for bolt in model.bolts:
		draw_set_transform(bolt.pos, bolt.velocity.angle())
		draw_texture_rect(pack.effects["bolt"] as Texture2D,
			Rect2(-Vector2(settings.bolt_size.y, settings.bolt_size.x) / 2,
				Vector2(settings.bolt_size.y, settings.bolt_size.x)), false)
		draw_set_transform(Vector2.ZERO)
	for hazard in model.hazards:
		var size: Vector2 = Vector2(settings.furniture_hit_width, settings.furniture_height) if hazard.furniture else settings.nut_size
		_texture_center(pack.effects["furniture" if hazard.furniture else "nut"] as Texture2D, hazard.pos, size)
	_draw_feedback()
	# Functional HUD panels sit over the painting.
	draw_rect(Rect2(0, 0, settings.arena_size.x, 112), pack.colors["hud_panel"])
	draw_rect(Rect2(0, settings.ground_y + 3, settings.arena_size.x, settings.arena_size.y - settings.ground_y), pack.colors["hud_panel"])
	if controls.last_device == "touch" or controls.touch_preview:
		var boundary: float = settings.ground_y - controls.settings.ground_tap_height
		draw_rect(Rect2(0, boundary, settings.arena_size.x, 2), pack.colors["touch_boundary"])
