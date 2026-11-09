class_name GameShell
extends Node
## Session/menu state around the existing round. The combat model stays unchanged.
var profile_path: String = "user://profile.cfg"
var profile: GameProfile
var catalog: PackCatalog
var catalog_path: String = "res://config/pack_catalog.json"
var active_pack_id: String = ""
var pack_picker: OptionButton
var pack_preview: TextureRect
var pack_description: Label
var game: Node2D
var style: ShellStyle
var mode: String = "home"
var return_mode: String = "home"
var last_device: String = "keyboard"
var recorded: bool = false
var new_record: bool = false
var ui_root: Control
var scrim: ColorRect
var center: CenterContainer
var card: PanelContainer
var content: VBoxContainer
var pause_button: Button
var help_label: Label
var status_label: Label
var record_label: Label
var result_detail: Label
var first_button: Button

func _ready() -> void:
	profile = GameProfile.new(profile_path)
	catalog = PackCatalog.new(catalog_path)
	if not catalog.errors.is_empty():
		push_error("; ".join(catalog.errors))
		return
	profile.selected_pack = catalog.resolve(profile.selected_pack)
	if not _create_game(profile.selected_pack): return
	if game.model == null or not game.pack.validation_errors().is_empty():
		return
	style = game.pack.ui["shell_style"] as ShellStyle
	last_device = "touch" if OS.has_feature("mobile") else ("gamepad" if not Input.get_connected_joypads().is_empty() else "keyboard")
	game.controls.last_device = last_device
	game.controls.pause_requested.connect(_request_pause)
	game.controls.restart_requested.connect(start_round)
	_install_menu_controls()
	_create_ui()
	_apply_preferences()
	_show("home")

func _create_game(id: String) -> bool:
	var selected := catalog.load_pack(id)
	if selected == null:
		push_error("Cannot start incomplete presentation pack: " + id)
		return false
	game = preload("res://scenes/main.tscn").instantiate()
	game.managed_session = true
	game.pack_override = selected
	add_child(game)
	active_pack_id = id
	return true

func _apply_selected_pack() -> bool:
	if active_pack_id == profile.selected_pack: return true
	if catalog.load_pack(profile.selected_pack) == null: return false
	# Whole-scene replacement prevents old animation/config resources leaking across packs.
	game.controls.clear()
	game.set_physics_process(false)
	remove_child(game)
	game.queue_free()
	if not _create_game(profile.selected_pack): return false
	style = game.pack.ui["shell_style"] as ShellStyle
	game.controls.pause_requested.connect(_request_pause)
	game.controls.restart_requested.connect(start_round)
	game.controls.last_device = last_device
	ui_root.theme = _theme()
	scrim.color = style.dim
	card.custom_minimum_size.x = style.panel_width
	pause_button.custom_minimum_size.y = style.button_height
	_apply_preferences()
	return true

func _install_menu_controls() -> void:
	# The built-in UI actions do not guarantee controller bindings in every export.
	var buttons: Dictionary = {"ui_accept": JOY_BUTTON_A, "ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN,
		"ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT}
	for action in buttons:
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = buttons[action]
		if not InputMap.action_has_event(action, button):
			InputMap.action_add_event(action, button)
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		var axis := InputEventJoypadMotion.new()
		axis.device = -1
		axis.axis = JOY_AXIS_LEFT_Y if action in ["ui_up", "ui_down"] else JOY_AXIS_LEFT_X
		axis.axis_value = -1 if action in ["ui_up", "ui_left"] else 1
		if not InputMap.action_has_event(action, axis):
			InputMap.action_add_event(action, axis)

func _create_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	ui_root.theme = _theme()
	scrim = ColorRect.new()
	scrim.color = style.dim
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(scrim)
	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(center)
	card = PanelContainer.new()
	card.custom_minimum_size.x = style.panel_width
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	card.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	pause_button = Button.new()
	pause_button.text = "Пауза  [P]"
	pause_button.position = Vector2(game.settings.arena_size.x - 200, 14)
	pause_button.custom_minimum_size = Vector2(178, style.button_height)
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(_request_pause)
	ui_root.add_child(pause_button)

func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = style.body_size
	theme.set_color("font_color", "Label", style.text)
	var panel := _box(style.panel, style.border)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 10
	theme.set_stylebox("panel", "PanelContainer", panel)
	for type in ["Button", "CheckButton", "OptionButton"]:
		theme.set_color("font_color", type, style.text)
		theme.set_color("font_hover_color", type, style.text)
		theme.set_color("font_focus_color", type, style.text)
		theme.set_color("font_pressed_color", type, style.panel)
		theme.set_stylebox("normal", type, _box(style.button, style.border))
		theme.set_stylebox("hover", type, _box(style.button.lightened(0.14), style.accent))
		theme.set_stylebox("pressed", type, _box(style.accent, style.accent))
		var focus := _box(Color(0, 0, 0, 0), style.accent)
		focus.set_border_width_all(3)
		theme.set_stylebox("focus", type, focus)
	return theme

func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func _label(text: String, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", style.heading_size if heading else style.body_size)
	label.add_theme_color_override("font_color", style.accent if heading else style.text)
	content.add_child(label)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = style.button_height
	button.pressed.connect(action)
	content.add_child(button)
	if first_button == null:
		first_button = button
	return button

func _show(next_mode: String) -> void:
	mode = next_mode
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	first_button = null
	help_label = null
	status_label = null
	record_label = null
	result_detail = null
	pack_picker = null
	pack_preview = null
	pack_description = null
	var playing: bool = mode == "playing"
	game.paused = not playing
	game.set_physics_process(playing)
	game.controls.clear()
	game.controls.process_mode = Node.PROCESS_MODE_INHERIT if playing else Node.PROCESS_MODE_DISABLED
	game.controls.accepting_gameplay = playing and game.model.result.is_empty()
	game.hud_layer.visible = playing
	game.footer.visible = profile.show_hints
	scrim.visible = not playing
	center.visible = not playing
	pause_button.visible = playing and game.model.result.is_empty()
	if playing:
		return
	match mode:
		"home":
			_label(style.title, true)
			_label(style.subtitle)
			record_label = _label(_record_text())
			_button("Играть", start_round)
			_button("Как играть", func() -> void: open_panel("help"))
			_button("Настройки", func() -> void: open_panel("settings"))
			var version := _label("Версия " + str(ProjectSettings.get_setting("application/config/version")))
			version.add_theme_color_override("font_color", style.muted)
		"pause":
			_label("ПАУЗА", true)
			_label("Раунд остановлен. Можно перевести дух.")
			_button("Продолжить", resume_round)
			_button("Как играть", func() -> void: open_panel("help"))
			_button("Настройки", func() -> void: open_panel("settings"))
			_button("Начать заново", start_round)
			_button("В главное меню", leave_round)
		"settings":
			_label("НАСТРОЙКИ", true)
			_pack_choice()
			_preference("Подсказки во время игры", "show_hints")
			_preference("Движение фона", "background_motion", game.ambient == null)
			if not OS.has_feature("mobile"):
				_preference("Управление касаниями через мышь", "touch_preview")
			status_label = _label(_pack_status())
			_button("Назад", close_panel)
		"help":
			_label("КАК ИГРАТЬ", true)
			help_label = _label(_controls_text())
			_label("Сбивай врагов в воздухе. Приземлившихся отбрасывай выстрелом вбок.\nДеталей брони: %d. Без брони следующий удар завершает раунд." % game.settings.armor_parts)
			_label("Когда мешок опустеет, стреляй в босса. Его приземления разрушают балкон.")
			_label("Результат — сбитые враги в минуту. Рекорд засчитывается только за победу.")
			_button("Назад", close_panel)
		"result":
			_label("ПОБЕДА!" if game.model.result == "win" else "ПОРАЖЕНИЕ", true)
			result_detail = _label("Балкон не выдержал!" if game.model.result == "win" else game.model.cause)
			_label("Сбито: %d   •   Время: %.1f с\nТемп: %.1f врагов в минуту" % [game.model.kills, game.model.elapsed, game.model.rate()])
			record_label = _label(("НОВЫЙ РЕКОРД!\n" if new_record else "") + _record_text())
			if profile.last_error != OK and profile.last_error != ERR_FILE_NOT_FOUND:
				_label("Не удалось сохранить рекорд на этом устройстве.")
			_button("Ещё раз", start_round)
			_button("В главное меню", leave_round)
	if first_button != null:
		call_deferred("_focus_menu")
	game.queue_redraw()

func _focus_menu() -> void:
	# Several transitions can happen in one frame; never focus a removed menu.
	if is_inside_tree() and is_instance_valid(first_button) and first_button.is_inside_tree() and first_button.is_visible_in_tree():
		first_button.grab_focus()

func _pack_status() -> String:
	return "Оформление изменится в следующем раунде." if profile.selected_pack != active_pack_id else "Изменения сохраняются на этом устройстве."

func _pack_choice() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)
	pack_preview = TextureRect.new()
	pack_preview.custom_minimum_size = Vector2(92, 108)
	pack_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pack_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pack_preview)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	pack_picker = OptionButton.new()
	pack_picker.custom_minimum_size.y = style.button_height
	for entry in catalog.entries:
		pack_picker.add_item(entry.name)
		pack_picker.set_item_metadata(pack_picker.item_count - 1, entry.id)
		if entry.id == profile.selected_pack: pack_picker.select(pack_picker.item_count - 1)
	column.add_child(pack_picker)
	pack_picker.item_selected.connect(func(index: int) -> void: select_pack(str(pack_picker.get_item_metadata(index))))
	pack_description = Label.new()
	pack_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pack_description.add_theme_color_override("font_color", style.muted)
	column.add_child(pack_description)
	_update_pack_preview()

func _update_pack_preview() -> void:
	var entry := catalog.entry_for(profile.selected_pack)
	pack_preview.texture = load(entry.preview) as Texture2D
	pack_description.text = entry.description

func select_pack(id: String) -> bool:
	# Reject broken/uninstalled packs without saving an unusable preference.
	if not catalog.has_pack(id) or catalog.load_pack(id) == null: return false
	profile.selected_pack = id
	profile.save_profile()
	if pack_picker != null:
		for index in pack_picker.item_count:
			if str(pack_picker.get_item_metadata(index)) == id: pack_picker.select(index)
		_update_pack_preview()
	if status_label != null:
		status_label.text = _pack_status() if profile.last_error == OK else "Не удалось сохранить выбор на этом устройстве."
	return true

func _preference(text: String, key: String, disabled: bool = false) -> void:
	var button := CheckButton.new()
	button.text = text
	button.custom_minimum_size.y = style.button_height
	button.button_pressed = profile.get(key)
	button.disabled = disabled
	button.toggled.connect(func(value: bool) -> void: set_preference(key, value))
	content.add_child(button)
	if first_button == null:
		first_button = button

func set_preference(key: String, value: bool) -> void:
	if key not in ["show_hints", "background_motion", "touch_preview"]:
		return
	profile.set(key, value)
	_apply_preferences()
	profile.save_profile()
	if status_label != null:
		status_label.text = "Сохранено на этом устройстве." if profile.last_error == OK else "Не удалось сохранить настройки на этом устройстве."

func _apply_preferences() -> void:
	game.controls.touch_preview = profile.touch_preview and not OS.has_feature("mobile")
	game.footer.visible = profile.show_hints
	if game.ambient != null:
		game.ambient.settings = game.pack.ambient.duplicate(true)
		game.ambient.settings.enabled = game.pack.ambient.enabled and profile.background_motion
	game.queue_redraw()

func start_round() -> void:
	if not _apply_selected_pack(): return
	game.scenario_picker.select(0)
	game.furniture_check.button_pressed = game.settings.furniture_enabled
	game._restart()
	recorded = false
	new_record = false
	game.controls.last_device = last_device
	_show("playing")

func resume_round() -> void:
	if game.model.result.is_empty():
		_show("playing")

func leave_round() -> void:
	if not _apply_selected_pack(): return
	game._restart()
	_show("home")

func _request_pause() -> void:
	if mode == "playing" and game.model.result.is_empty():
		_show("pause")

func open_panel(panel: String) -> void:
	return_mode = mode
	_show(panel)

func close_panel() -> void:
	if return_mode == "home": _apply_selected_pack()
	_show(return_mode)

func _record_text() -> String:
	var best: Dictionary = profile.best(game.settings)
	return "Рекорд появится после первой победы" if best.is_empty() else "Рекорд: %.1f в минуту  •  %d сбито за %.1f с" % [best.rate, best.kills, best.seconds]

func _controls_text() -> String:
	match last_device:
		"gamepad":
			return "Стик / крестовина — бег\nA / × — выстрел: без направления вверх, с направлением вбок\nY / △ — повтор   •   Start / Options — пауза"
		"touch":
			return "Перетаскивай героя пальцем по горизонтали.\nКороткий тап выше наземной полосы — выстрел вверх,\nтап в полосе слева или справа — выстрел вбок.\nВторой палец может стрелять во время движения."
	return "A / D или стрелки — бег\nПробел — вверх; с зажатым направлением — вбок\nR — повтор   •   P / Escape — пауза"

func _input(event: InputEvent) -> void:
	if game == null or game.controls == null:
		return
	if event is InputEventKey and event.pressed:
		last_device = "keyboard"
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > game.controls.settings.stick_deadzone):
		last_device = "gamepad"
	elif event is InputEventScreenTouch:
		last_device = "touch"
	if help_label != null:
		help_label.text = _controls_text()
	if mode in ["help", "settings", "pause"] and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		if mode == "pause": resume_round()
		else: close_panel()
		get_viewport().set_input_as_handled()
	elif mode == "pause" and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		resume_round()
		get_viewport().set_input_as_handled()
	elif mode in ["result", "pause"] and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		start_round()
		get_viewport().set_input_as_handled()
	elif mode != "playing" and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_P, KEY_ESCAPE]:
			if mode == "pause": resume_round()
			elif mode in ["help", "settings"]: close_panel()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R and mode in ["pause", "result"]:
			start_round()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if game == null or game.model == null or mode != "playing":
		return
	if not game.model.result.is_empty():
		game.controls.accepting_gameplay = false
		pause_button.visible = false
		if not recorded:
			recorded = true
			new_record = profile.record_victory(game.model)
		if game.model.result != "lose" or game.feedback == null or game.feedback.result_ready():
			_show("result")
