class_name AssetPack
extends Resource
## Presentation only. Mechanical values belong to GameplayConfig.
@export var pack_id: StringName
@export_enum("prototype", "static", "animated") var readiness: String = "prototype"
@export var display_names: Dictionary[String, String]
@export var colors: Dictionary[String, Color]
@export var balloon_palette: PackedColorArray
@export_group("Categorized media")
@export var characters: Dictionary[String, Resource]
@export var environment: Dictionary[String, Resource]
@export var effects: Dictionary[String, Resource]
@export var ui: Dictionary[String, Resource]
@export var sfx: Dictionary[String, AudioStream]
@export var music: Dictionary[String, AudioStream]
@export_group("Static pack")
@export var character_variants: Dictionary[String, Array]
@export var balloon_sprites: Array[Texture2D]
## Normalized position of the bottom knot in a balloon texture.
@export var balloon_rope_anchor: Vector2
@export var feedback: FeedbackConfig
@export var balloon_pop_frames: Dictionary[String, Array]
@export var player_anchor: Vector2
@export var player_body_height: float
@export var balcony_draw_height: float
@export var show_names: bool = true
@export_enum("silent", "supplied") var audio_mode: String = "silent"

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if pack_id == &"" or balloon_palette.is_empty():
		errors.append("Pack requires ID and balloon palette.")
	for role in ["player", "boss", "normal", "tank", "thrower"]:
		if not display_names.has(role):
			errors.append("Missing display name: " + role)
	for key in ["player", "boss", "normal", "tank", "thrower", "background", "ground",
			"balcony", "bolt", "nut", "armor", "furniture", "text"]:
		if not colors.has(key):
			errors.append("Missing presentation color: " + key)
	if readiness == "prototype":
		return errors
	if readiness != "static":
		errors.append("Animated pack contract is not implemented yet.")
		return errors
	var character_keys: Array[String] = ["player", "boss", "boss_defeated", "normal", "tank", "thrower"]
	for key in ["hud_panel", "result_panel", "touch_boundary"]:
		if not colors.has(key):
			errors.append("Missing static UI color: " + key)
	for pose in ["right", "left", "up"]:
		character_keys.append("player_" + pose)
		for part in 3:
			character_keys.append("armor_%d_%s" % [part, pose])
	_check_textures(characters, character_keys, "characters", errors)
	_check_textures(effects, ["crossbow_right", "crossbow_left", "crossbow_up", "crossbow",
		"bolt", "nut", "sack", "furniture", "rope", "armor_0", "armor_1", "armor_2"], "effects", errors)
	var environment_keys: Array[String] = ["background", "ground"]
	for stage in 6:
		environment_keys.append("balcony_" + str(stage))
	_check_textures(environment, environment_keys, "environment", errors)
	if balloon_rope_anchor.x <= 0 or balloon_rope_anchor.x >= 1 or balloon_rope_anchor.y <= 0 or balloon_rope_anchor.y > 1:
		errors.append("Balloon rope anchor must lie inside the normalized texture frame.")
	if balloon_sprites.size() != balloon_palette.size():
		errors.append("Balloon textures and palette must have matching counts.")
	for texture in balloon_sprites:
		if texture == null:
			errors.append("Missing balloon texture.")
	for role in ["normal", "tank", "thrower"]:
		if not character_variants.has(role) or character_variants[role].is_empty():
			errors.append("Missing minion variants: " + role)
		else:
			for texture in character_variants[role]:
				if not texture is Texture2D:
					errors.append("Invalid minion variant: " + role)
	if feedback != null or not balloon_pop_frames.is_empty():
		if feedback == null:
			errors.append("Animation frames require feedback configuration.")
		else:
			errors.append_array(feedback.validation_errors())
		for index in balloon_sprites.size():
			var frames: Array = balloon_pop_frames.get(str(index), [])
			if frames.size() < 2:
				errors.append("Missing balloon pop sequence: " + str(index))
			for texture in frames:
				if not texture is Texture2D:
					errors.append("Invalid balloon pop frame.")
	var player_frame := characters.get("player_right") as Texture2D
	if player_frame != null:
		for key in character_keys:
			if key.begins_with("player_") or key.begins_with("armor_"):
				var texture := characters.get(key) as Texture2D
				if texture != null and texture.get_size() != player_frame.get_size():
					errors.append("Misaligned player layer dimensions: " + key)
		for pose in ["right", "left", "up"]:
			var texture := effects.get("crossbow_" + pose) as Texture2D
			if texture != null and texture.get_size() != player_frame.get_size():
				errors.append("Misaligned weapon dimensions: " + pose)
		if player_anchor.x <= 0 or player_anchor.y <= 0 or player_anchor.x >= player_frame.get_width() or player_anchor.y >= player_frame.get_height():
			errors.append("Player anchor must lie inside the frame.")
	if player_body_height <= 0 or balcony_draw_height <= 0:
		errors.append("Static pack needs positive visual geometry.")
	if audio_mode == "supplied" and sfx.is_empty():
		errors.append("Supplied audio pack needs sound effects.")
	return errors

func _check_textures(category: Dictionary, keys: Array[String], label: String, errors: Array[String]) -> void:
	for key in keys:
		if not category.get(key) is Texture2D:
			errors.append("Missing texture in " + label + ": " + key)
