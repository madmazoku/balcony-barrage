extends SceneTree
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	var path := "user://qa-profile-%d.cfg" % OS.get_process_id()
	var profile := GameProfile.new(path)
	check(profile.show_hints and profile.background_motion and not profile.touch_preview, "A missing profile must start with safe defaults.")
	profile.show_hints = false
	profile.touch_preview = true
	check(profile.save_profile() == OK, "Preferences must save.")
	var reopened := GameProfile.new(path)
	check(not reopened.show_hints and reopened.touch_preview, "Preferences must survive reconstruction from disk.")
	var config: GameplayConfig = load("res://config/gameplay.tres").duplicate(true)
	var model := RoundModel.new(config)
	model.elapsed = 10
	model.kills = 4
	model.result = "lose"
	check(not reopened.record_victory(model) and reopened.best(config).is_empty(), "Defeat must never set a victory record.")
	model.result = "win"
	check(reopened.record_victory(model), "A normal-round victory must establish a record.")
	reopened = GameProfile.new(path)
	check(reopened.best(config).kills == 4 and is_equal_approx(float(reopened.best(config).rate), 24.0), "The rate record must survive loading.")
	model.elapsed = 20
	check(not reopened.record_victory(model), "A slower victory must not replace a better record.")
	model.elapsed = 5
	model.scenario = "boss"
	check(not reopened.record_victory(model), "QA scenarios cannot set a normal-round record.")
	model.scenario = "round"
	model.furniture_enabled = not config.furniture_enabled
	check(not reopened.record_victory(model), "Changed furniture rules must not share a record.")
	var modified: GameplayConfig = config.duplicate(true)
	modified.shot_cooldown += 0.01
	check(GameProfile.rules_key(config) == GameProfile.rules_key(config.duplicate(true)), "Identical rules must have the same stable key.")
	check(GameProfile.rules_key(config) != GameProfile.rules_key(modified) and reopened.best(modified).is_empty(), "Changed balance must have a separate record.")
	var invalid := ConfigFile.new()
	invalid.set_value("preferences", "show_hints", "wrong type")
	invalid.set_value("scores", "victories", {"bad": {"kills": -10, "seconds": 0.0, "rate": INF}, "text": "invalid"})
	invalid.save(path)
	reopened = GameProfile.new(path)
	check(reopened.show_hints and reopened.records.is_empty(), "Malformed saved fields must be ignored.")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[broken\n")
	file.close()
	# This fixture intentionally exercises ConfigFile's parse error diagnostic.
	var print_errors: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	reopened = GameProfile.new(path)
	Engine.print_error_messages = print_errors
	check(reopened.last_error == ERR_PARSE_ERROR and reopened.show_hints and reopened.records.is_empty(), "A corrupt profile must not prevent startup.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	if failures.is_empty(): print("PROFILE_TESTS_OK")
	quit(0 if failures.is_empty() else 1)
