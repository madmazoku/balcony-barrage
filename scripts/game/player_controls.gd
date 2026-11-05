class_name PlayerControls
extends Node
## Converts device input into the same cardinal shots and bounded movement.
signal shot_requested(direction: Vector2)
signal pause_requested
signal restart_requested

var settings: ControlsConfig = preload("res://config/controls.tres")
var gameplay: GameplayConfig
var accepting_gameplay: bool = true
var touch_preview: bool = false
var last_device: String = "keyboard"
var fingers: Dictionary = {}
var primary_finger: int = -1
var drag_target: float = 0.0
var dragging: bool = false
var active_pad: int = -1
var pads: Dictionary = {}
var player_x: float = 0.0

func _ready() -> void:
	Input.joy_connection_changed.connect(_pad_connection)
	get_window().focus_exited.connect(_focus_lost)

func _focus_lost() -> void:
	clear()
	if accepting_gameplay:
		pause_requested.emit()

func clear() -> void:
	fingers.clear()
	primary_finger = -1
	dragging = false
	pads.clear()
	active_pad = -1

func _pad_connection(device: int, connected: bool) -> void:
	if not connected:
		pads.erase(device)
		if active_pad == device:
			active_pad = -1
			if accepting_gameplay:
				pause_requested.emit()

func _input(event: InputEvent) -> void:
	# Track releases before GUI consumption, so crossing the toolbar cannot stick input.
	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_LEFT_X:
			_pad(event.device).axis = event.axis_value
			if absf(event.axis_value) > settings.stick_deadzone:
				active_pad = event.device
				last_device = "gamepad"
	elif event is InputEventJoypadButton:
		if event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			var pad: Dictionary = _pad(event.device)
			pad["left" if event.button_index == JOY_BUTTON_DPAD_LEFT else "right"] = event.pressed
			active_pad = event.device
			last_device = "gamepad"
		if not event.pressed and event.button_index == JOY_BUTTON_A:
			_pad(event.device).shot_down = false
	elif event is InputEventScreenTouch:
		if fingers.has(event.index) and (not event.pressed or event.canceled):
			_end_touch(event.index, event.position, event.canceled)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and fingers.has(event.index):
		_drag_touch(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif touch_preview and event is InputEventMouseButton and event.device != -1:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and fingers.has(-2):
			_end_touch(-2, event.position, false)
			get_viewport().set_input_as_handled()
	elif touch_preview and event is InputEventMouseMotion and event.device != -1 and fingers.has(-2):
		_drag_touch(-2, event.position)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		last_device = "keyboard"
		match event.physical_keycode:
			KEY_R:
				restart_requested.emit()
			KEY_P, KEY_ESCAPE:
				pause_requested.emit()
			KEY_SPACE:
				if accepting_gameplay:
					_fire_from_movement()
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		active_pad = event.device
		last_device = "gamepad"
		match event.button_index:
			JOY_BUTTON_START:
				pause_requested.emit()
			JOY_BUTTON_Y:
				restart_requested.emit()
			JOY_BUTTON_A:
				var pad: Dictionary = _pad(event.device)
				if accepting_gameplay and not pad.shot_down:
					pad.shot_down = true
					_fire_from_movement()
			_:
				return
		get_viewport().set_input_as_handled()
	elif accepting_gameplay and event is InputEventScreenTouch and event.pressed and not event.canceled:
		_begin_touch(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif accepting_gameplay and touch_preview and event is InputEventMouseButton and event.device != -1:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_touch(-2, event.position)
			get_viewport().set_input_as_handled()

func _pad(device: int) -> Dictionary:
	if not pads.has(device):
		pads[device] = {"axis": 0.0, "left": false, "right": false, "shot_down": false}
	return pads[device]

func digital_movement() -> float:
	var left: bool = Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right: bool = Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	var keyboard: float = float(right) - float(left)
	if not is_zero_approx(keyboard):
		return keyboard
	if active_pad < 0 or not pads.has(active_pad):
		return 0.0
	var pad: Dictionary = pads[active_pad]
	var dpad: float = float(pad.right) - float(pad.left)
	if not is_zero_approx(dpad):
		return dpad
	var axis: float = pad.axis
	if absf(axis) <= settings.stick_deadzone:
		return 0.0
	return signf(axis) * (absf(axis) - settings.stick_deadzone) / (1.0 - settings.stick_deadzone)

func movement(current_x: float, delta: float) -> float:
	player_x = current_x
	if not accepting_gameplay:
		return 0.0
	var digital: float = digital_movement()
	if not is_zero_approx(digital):
		return digital
	if dragging:
		return clampf((drag_target - current_x) / (gameplay.player_speed * delta), -1.0, 1.0)
	return 0.0

func _fire_from_movement() -> void:
	var direction: float = digital_movement()
	shot_requested.emit(Vector2.UP if is_zero_approx(direction) else Vector2(signf(direction), 0))

func _begin_touch(index: int, position: Vector2) -> void:
	if not Rect2(Vector2.ZERO, gameplay.arena_size).has_point(position):
		return
	last_device = "touch"
	fingers[index] = {"start": position, "position": position, "player_start": player_x,
		"time": Time.get_ticks_msec(), "moved": false}
	if primary_finger == -1:
		primary_finger = index
		drag_target = player_x

func _drag_touch(index: int, position: Vector2) -> void:
	var finger: Dictionary = fingers[index]
	finger.position = position
	if position.distance_to(finger.start) >= settings.drag_threshold:
		finger.moved = true
	if index == primary_finger and finger.moved:
		dragging = true
		drag_target = clampf(finger.player_start + position.x - finger.start.x,
			gameplay.player_size.x / 2, gameplay.arena_size.x - gameplay.player_size.x / 2)

func _end_touch(index: int, position: Vector2, canceled: bool) -> void:
	var finger: Dictionary = fingers[index]
	var is_tap: bool = not finger.moved and position.distance_to(finger.start) < settings.drag_threshold
	is_tap = is_tap and (Time.get_ticks_msec() - finger.time) / 1000.0 <= settings.tap_seconds
	fingers.erase(index)
	if index == primary_finger:
		primary_finger = -1
		dragging = false
	if accepting_gameplay and is_tap and not canceled:
		var direction: Vector2 = Vector2.UP
		if position.y >= gameplay.ground_y - settings.ground_tap_height:
			direction = Vector2.LEFT if position.x < player_x else Vector2.RIGHT
		shot_requested.emit(direction)
