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

func _ready() -> void:
	pack = presentation.active_pack
	if pack == null:
		push_error("No active presentation pack.")
		set_physics_process(false)
		return
	if pack.balloon_palette.is_empty():
		push_error("Active pack has no balloon palette.")
		set_physics_process(false)
		return
	for role in ["player", "boss", "normal", "tank", "thrower"]:
		if not pack.display_names.has(role):
			push_error("Missing presentation label: " + role)
			set_physics_process(false)
			return
	for key in ["player", "boss", "normal", "tank", "thrower", "background", "ground", "balcony", "bolt", "nut", "armor", "furniture", "text"]:
		if not pack.colors.has(key):
			push_error("Missing presentation color: " + key)
			set_physics_process(false)
			return
	model = RoundModel.new(settings)
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
	title.text = "BALCONY BARRAGE  /  ПРОВЕРКА МЕХАНИКИ"
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 14)
	panel.add_child(controls)
	scenario_picker = OptionButton.new()
	for label in ["Полный раунд", "Две цели на линии", "Последний шарик у земли", "Захват + гайка", "Пустой мешок / босс", "Три типа вместе"]:
		scenario_picker.add_item(label)
	scenario_picker.item_selected.connect(func(_index: int) -> void: _restart())
	controls.add_child(scenario_picker)
	var restart := Button.new()
	restart.text = "Заново [R]"
	restart.pressed.connect(_restart)
	controls.add_child(restart)
	furniture_check = CheckButton.new()
	furniture_check.text = "Мебель в финале"
	furniture_check.button_pressed = settings.furniture_enabled
	furniture_check.toggled.connect(func(enabled: bool) -> void:
		model.furniture_enabled = enabled)
	controls.add_child(furniture_check)
	var pause_button := Button.new()
	pause_button.text = "Пауза [P]"
	pause_button.pressed.connect(func() -> void: paused = not paused)
	controls.add_child(pause_button)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 18)
	panel.add_child(hud)
	footer = Label.new()
	footer.modulate = pack.colors["text"]
	footer.position = Vector2(22, settings.ground_y + 10)
	footer.add_theme_font_size_override("font_size", 17)
	layer.add_child(footer)
	# Keyboard focus stays with the game after clicking a prototype control.
	for control in controls.get_children():
		control.focus_mode = Control.FOCUS_NONE
	_update_hud()

func _restart() -> void:
	var enabled: bool = furniture_check.button_pressed
	model.restart(scenario_ids[scenario_picker.selected])
	model.furniture_enabled = enabled
	paused = false
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or model == null:
		return
	match event.physical_keycode:
		KEY_R:
			_restart()
		KEY_P, KEY_ESCAPE:
			paused = not paused
		KEY_SPACE:
			if not paused:
				var movement: float = _movement()
				model.shoot(Vector2.UP if is_zero_approx(movement) else Vector2(signf(movement), 0))
	_update_hud()
	queue_redraw()

func _movement() -> float:
	var left: bool = Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right: bool = Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	return float(right) - float(left)

func _physics_process(delta: float) -> void:
	if model == null:
		return
	if not paused:
		model.tick(delta, _movement())
	_update_hud()
	queue_redraw()

func _update_hud() -> void:
	hud.text = "Броня %d  ·  Мешок %d  ·  Балкон %d/%d  ·  Сбито %d  ·  %.1f c  ·  %.1f / мин" % [
		model.armor, settings.release_roles.size() - model.released,
		settings.balcony_stages - model.broken_stages, settings.balcony_stages,
		model.kills, model.elapsed, model.rate()]
	footer.text = "A/D или ←/→ — бег    Пробел — вверх; с направлением — вбок    R — повтор    P — пауза"
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
	draw_rect(Rect2(Vector2.ZERO, settings.arena_size), pack.colors["background"])
	draw_rect(Rect2(0, settings.ground_y, settings.arena_size.x, settings.arena_size.y - settings.ground_y), pack.colors["ground"])
	var segment_width: float = (settings.balcony_right - settings.balcony_left) / settings.balcony_stages
	for stage in settings.balcony_stages:
		var color: Color = pack.colors["balcony"]
		if stage < model.broken_stages:
			color.a = 0.2
		draw_rect(Rect2(settings.balcony_left + stage * segment_width, settings.balcony_y, segment_width - 5, 18), color)
	_text(Vector2(settings.balcony_left, settings.balcony_y + 48),
		"Мешок пуст — попади в босса" if model.released >= settings.release_roles.size() else "Босс защищён, пока мешок не опустел")
	var boss_position: Vector2 = model.boss_draw_position()
	if model.result == "win":
		boss_position.y = settings.ground_y - settings.boss_size.y / 2
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
				draw_line(enemy.pos, balloon, pack.colors["text"], 1.0)
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
	if model.result != "":
		draw_rect(Rect2(300, 350, 680, 180), Color(0.04, 0.06, 0.09, 0.96))
		_text(Vector2(340, 395), "ПОБЕДА — балкон рухнул!" if model.result == "win" else "ПОРАЖЕНИЕ — " + model.cause, 26)
		_text(Vector2(340, 437), "Сбито %d  /  %.1f сек  /  %.1f в минуту" % [model.kills, model.elapsed, model.rate()], 22)
		_text(Vector2(340, 485), "R — попробовать снова", 22)
