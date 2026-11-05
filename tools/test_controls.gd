extends SceneTree

var failures: Array[String] = []
var game: Node
var controls: PlayerControls
var model: RoundModel
var shots: Array[Vector2] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)
	await process_frame

func drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	root.push_input(event, true)
	await process_frame

func joy_axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 7
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	Input.parse_input_event(event)
	await process_frame

func joy_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 7
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	controls = game.get("controls")
	model = game.get("model")
	controls.shot_requested.connect(func(direction: Vector2) -> void: shots.append(direction))
	model.restart("boss")
	# Downward stick drift must yield a vertical shot after returning to the deadzone.
	await joy_axis(0.9)
	check(controls.digital_movement() > 0, "Analog stick must move right.")
	await joy_button(JOY_BUTTON_A, true)
	check(shots.back() == Vector2.RIGHT, "Gamepad fire must follow held direction.")
	var count: int = shots.size()
	await joy_button(JOY_BUTTON_A, true)
	check(shots.size() == count, "Holding gamepad fire must not repeat.")
	await joy_button(JOY_BUTTON_A, false)
	await joy_axis(0.05)
	check(is_zero_approx(controls.digital_movement()), "Stick drift inside deadzone must stop.")
	await joy_button(JOY_BUTTON_A, true)
	check(shots.back() == Vector2.UP, "Centered stick must fire up.")
	await joy_button(JOY_BUTTON_A, false)
	await joy_button(JOY_BUTTON_DPAD_LEFT, true)
	check(controls.digital_movement() == -1, "D-pad must override analog drift.")
	await joy_button(JOY_BUTTON_DPAD_LEFT, false)
	await joy_axis(0)
	controls._pad_connection(7, false)
	check(controls.active_pad == -1 and is_zero_approx(controls.digital_movement()), "Disconnect must stop gamepad movement.")
	check(game.get("paused"), "Disconnecting active controller must pause.")
	game.call("_toggle_pause")

	var player_start: float = model.player.x
	await touch(0, Vector2(400, 500), true)
	check(is_equal_approx(controls.drag_target, player_start), "Touch must preserve player offset.")
	await drag(0, Vector2(600, 500))
	check(controls.dragging and is_equal_approx(controls.drag_target, player_start + 200), "Drag target must preserve initial offset.")
	check(absf(controls.movement(model.player.x, 1.0 / 60)) <= 1, "Drag must obey player speed.")
	count = shots.size()
	await touch(1, Vector2(400, 400), true)
	await touch(1, Vector2(400, 400), false)
	check(shots.size() == count + 1 and shots.back() == Vector2.UP, "Second finger must fire up while dragging.")
	check(controls.dragging, "Second finger release must preserve primary drag.")
	count = shots.size()
	await touch(0, Vector2(600, 500), false)
	check(not controls.dragging and shots.size() == count, "Releasing a drag must stop without firing.")

	await touch(0, Vector2(60, 700), true)
	await touch(0, Vector2(60, 700), false)
	check(shots.back() == Vector2.LEFT, "Ground tap left must fire left.")
	await touch(0, Vector2(1220, 700), true)
	await touch(0, Vector2(1220, 700), false)
	check(shots.back() == Vector2.RIGHT, "Ground tap right must fire right.")
	count = shots.size()
	await touch(0, Vector2(300, 400), true)
	await touch(0, Vector2(300, 400), false, true)
	check(shots.size() == count, "Canceled touch must not fire.")
	await touch(0, Vector2(300, 400), true)
	controls.fingers[0].time -= int((controls.settings.tap_seconds + 0.1) * 1000)
	await touch(0, Vector2(300, 400), false)
	check(shots.size() == count, "Long press must not count as a tap.")
	await touch(0, Vector2(300, 400), true)
	game.call("_toggle_pause")
	await touch(0, Vector2(300, 400), false)
	check(shots.size() == count and controls.fingers.is_empty(), "Pause must cancel pending touch.")
	game.call("_toggle_pause")
	await touch(0, Vector2(300, 400), true)
	game.call("_restart")
	await touch(0, Vector2(300, 400), false)
	check(shots.size() == count and controls.fingers.is_empty(), "Restart must cancel pending touch.")
	# Releasing a tracked finger over the toolbar must still clear the gesture.
	await touch(0, Vector2(400, 500), true)
	await drag(0, Vector2(400, 40))
	await touch(0, Vector2(400, 40), false)
	check(controls.fingers.is_empty() and not controls.dragging, "GUI crossing must not stick a drag.")
	controls.touch_preview = true
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(300, 400)
	mouse.pressed = true
	root.push_input(mouse, true)
	await process_frame
	mouse = mouse.duplicate()
	mouse.pressed = false
	count = shots.size()
	root.push_input(mouse, true)
	await process_frame
	check(shots.size() == count + 1 and shots.back() == Vector2.UP, "Desktop touch preview must use the same tap direction.")
	await joy_button(JOY_BUTTON_START, true)
	check(game.get("paused"), "Start must pause the game.")
	await joy_button(JOY_BUTTON_START, false)
	await joy_button(JOY_BUTTON_START, true)
	check(not game.get("paused"), "Start must resume the game.")
	await joy_button(JOY_BUTTON_START, false)
	model.kills = 5
	await joy_button(JOY_BUTTON_Y, true)
	check(model.kills == 0, "Gamepad restart must reset the round.")
	await joy_button(JOY_BUTTON_Y, false)

	print("PHYSICAL_GAMEPADS_DETECTED=", Input.get_connected_joypads())
	for device in Input.get_connected_joypads():
		print("GAMEPAD ", device, ": ", Input.get_joy_name(device), " mapped=", Input.is_joy_known(device))
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("CONTROLS_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
