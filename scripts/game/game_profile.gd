class_name GameProfile
extends RefCounted
## Local preferences and victory records. Never changes gameplay configuration.
var path: String
var show_hints: bool = true
var touch_preview: bool = false
var background_motion: bool = true
var records: Dictionary = {}
var last_error: Error = OK

func _init(storage_path: String = "user://profile.cfg") -> void:
	path = storage_path
	load_profile()

func load_profile() -> void:
	var file := ConfigFile.new()
	last_error = file.load(path)
	if last_error != OK:
		return
	for key in ["show_hints", "touch_preview", "background_motion"]:
		var value: Variant = file.get_value("preferences", key, get(key))
		if value is bool:
			set(key, value)
	var stored: Variant = file.get_value("scores", "victories", {})
	if stored is Dictionary:
		for key in stored:
			if key is String and _valid_record(stored[key]):
				records[key] = stored[key]

func save_profile() -> Error:
	var file := ConfigFile.new()
	file.set_value("profile", "schema", 1)
	for key in ["show_hints", "touch_preview", "background_motion"]:
		file.set_value("preferences", key, get(key))
	file.set_value("scores", "victories", records)
	# A failed write must leave the previous profile intact.
	last_error = file.save(path + ".tmp")
	if last_error == OK:
		last_error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	return last_error

static func rules_key(config: GameplayConfig) -> String:
	var values: Dictionary = {}
	for property in config.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			values[property.name] = var_to_str(config.get(property.name))
	return JSON.stringify(values, "", true).sha256_text()

func best(config: GameplayConfig) -> Dictionary:
	return records.get(rules_key(config), {}).duplicate(true)

func record_victory(model: RoundModel) -> bool:
	if model.result != "win" or model.scenario != "round" or model.elapsed <= 0 or not is_finite(model.elapsed):
		return false
	if model.furniture_enabled != model.config.furniture_enabled:
		return false
	var candidate: Dictionary = {"kills": model.kills, "seconds": model.elapsed, "rate": model.rate()}
	if not _valid_record(candidate):
		return false
	var key: String = rules_key(model.config)
	var previous: Dictionary = records.get(key, {})
	if not previous.is_empty() and float(previous.rate) >= model.rate():
		return false
	records[key] = candidate
	save_profile()
	return true

func _valid_record(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["kills", "seconds", "rate"]):
		return false
	if not value.kills is int or value.kills < 0:
		return false
	for key in ["seconds", "rate"]:
		if not (value[key] is float or value[key] is int) or not is_finite(float(value[key])):
			return false
	return value.seconds > 0 and value.rate >= 0 and is_equal_approx(float(value.rate), value.kills * 60.0 / value.seconds)
