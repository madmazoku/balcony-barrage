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
## Optional presentation dimensions; zero preserves the original balloon proportions.
@export var balloon_draw_size: Vector2 = Vector2.ZERO
@export_enum("upright", "along_tether") var suspension_orientation: String = "upright"
## Presentation size only; projectile collision and speed stay in GameplayConfig.
@export var projectile_draw_sizes: Dictionary[String, Vector2]
@export var projectile_visual: ProjectileVisualConfig
## Normalized position of the bottom knot in a balloon texture.
@export var balloon_rope_anchor: Vector2
@export var feedback: FeedbackConfig
@export var balloon_pop_frames: Dictionary[String, Array]
## Full action canvases use normalized bounds of their matching neutral role.
@export var enemy_action_frames: Dictionary[String, Array]
@export var enemy_frame_bounds: Dictionary[String, Rect2]
## Keep the neutral sprite aspect at the mechanical body height; collision geometry is unchanged.
@export var preserve_actor_aspect: PackedStringArray
@export var boss_actions: BossActionConfig
@export var boss_action_frames: Dictionary[String, Texture2D]
@export var ambient: AmbientConfig
@export var locomotion: MotionConfig
@export var run_frames: Dictionary[String, Array]
@export var player_anchor: Vector2
@export var player_body_height: float
@export var balcony_draw_height: float
@export var show_names: bool = true
@export_enum("silent", "supplied") var audio_mode: String = "silent"

func suspension_draw_size(radius: float) -> Vector2:
	return balloon_draw_size if balloon_draw_size != Vector2.ZERO else Vector2(radius * 2, radius * 2.6)

func suspension_pose(position: Vector2, connection: Vector2, radius: float) -> Dictionary:
	var size: Vector2 = suspension_draw_size(radius)
	var local_anchor: Vector2 = (balloon_rope_anchor - Vector2(0.5, 0.5)) * size
	var toward: Vector2 = connection - position
	var angle: float = 0.0
	if suspension_orientation == "along_tether" and not local_anchor.is_zero_approx() and not toward.is_zero_approx():
		angle = local_anchor.angle_to(toward)
	return {"size": size, "angle": angle, "anchor": position + local_anchor.rotated(angle)}

func actor_draw_size(role: String, collision_size: Vector2) -> Vector2:
	if role not in preserve_actor_aspect:
		return collision_size
	var texture := characters.get(role) as Texture2D
	if texture == null or texture.get_height() <= 0:
		return collision_size
	return Vector2(collision_size.y * texture.get_width() / texture.get_height(), collision_size.y)

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
	if not ui.get("shell_style") is ShellStyle:
		errors.append("Pack requires its own shell UI style.")
	else:
		errors.append_array((ui["shell_style"] as ShellStyle).validation_errors())
	for key in projectile_draw_sizes:
		var size: Vector2 = projectile_draw_sizes[key]
		if not size.is_finite() or size.x <= 0 or size.y <= 0:
			errors.append("Invalid projectile draw size: " + key)
	if projectile_visual != null:
		errors.append_array(projectile_visual.validation_errors())
	if balloon_draw_size != Vector2.ZERO and (not balloon_draw_size.is_finite() or balloon_draw_size.x <= 0 or balloon_draw_size.y <= 0):
		errors.append("Invalid suspension draw size.")
	if suspension_orientation not in ["upright", "along_tether"]:
		errors.append("Invalid suspension orientation.")
	if suspension_orientation == "along_tether" and balloon_rope_anchor.is_equal_approx(Vector2(0.5, 0.5)):
		errors.append("Tether-oriented suspensions require an off-center anchor.")
	for role in preserve_actor_aspect:
		var texture := characters.get(role) as Texture2D
		if role not in ["normal", "tank", "thrower", "boss"] or texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			errors.append("Invalid aspect-preserved actor: " + role)
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
	if ambient != null:
		errors.append_array(ambient.validation_errors())
		var ambient_keys: Array[String] = ["ambient_background"]
		for id in ambient.layer_ids:
			ambient_keys.append("ambient_" + id)
		_check_textures(environment, ambient_keys, "ambient environment", errors)
		var background := environment.get("ambient_background") as Texture2D
		if background != null and background.get_size() != ambient.source_size:
			errors.append("Ambient clean background must match its source canvas.")
		for id in ambient.layer_ids:
			var layer := environment.get("ambient_" + id) as Texture2D
			var area: Rect2 = ambient.layer_rects.get(id, Rect2())
			if layer != null and not layer.get_size().is_equal_approx(area.size * ambient.source_size):
				errors.append("Misaligned ambient layer: " + id)
	if not balloon_rope_anchor.is_finite() or balloon_rope_anchor.x <= 0 or balloon_rope_anchor.x >= 1 or balloon_rope_anchor.y <= 0 or balloon_rope_anchor.y > 1:
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
	if feedback != null and feedback.enemy_actions_enabled:
		for role in ["normal", "tank", "thrower"]:
			var bounds: Rect2 = enemy_frame_bounds.get(role, Rect2())
			if bounds.size.x <= 0 or bounds.size.y <= 0 or not Rect2(0, 0, 1, 1).encloses(bounds):
				errors.append("Invalid action reference bounds: " + role)
		for key in ["thrower_windup", "thrower_release", "normal_capture", "tank_capture", "thrower_capture"]:
			var role: String = key.get_slice("_", 0)
			var frames: Array = enemy_action_frames.get(key, [])
			if frames.is_empty() or frames.size() != character_variants.get(role, []).size():
				errors.append("Missing action palettes: " + key)
			for texture in frames:
				if not texture is Texture2D:
					errors.append("Invalid action frame: " + key)
	if locomotion != null:
		errors.append_array(locomotion.validation_errors())
		for pose in ["right", "left", "up"]:
			var texture := characters.get("player_" + pose) as Texture2D
			_check_run_frames("player_" + pose, texture.get_size() if texture != null else Vector2.ZERO, errors)
		for role in ["normal", "tank", "thrower"]:
			var bounds: Rect2 = enemy_frame_bounds.get(role, Rect2())
			if bounds.size.x <= 0 or bounds.size.y <= 0 or not Rect2(0, 0, 1, 1).encloses(bounds):
				errors.append("Invalid running reference bounds: " + role)
			for index in character_variants.get(role, []).size():
				_check_run_frames(role + "_" + str(index), Vector2.ZERO, errors)
		if locomotion.boss_enabled:
			var bounds: Rect2 = enemy_frame_bounds.get("boss", Rect2())
			if bounds.size.x <= 0 or bounds.size.y <= 0 or not Rect2(0, 0, 1, 1).encloses(bounds):
				errors.append("Invalid boss running reference bounds.")
			_check_run_frames("boss_0", Vector2.ZERO, errors)
	elif not run_frames.is_empty():
		errors.append("Running frames require locomotion settings.")
	if feedback != null and feedback.defeat_enabled and (locomotion == null or not feedback.enemy_actions_enabled):
		errors.append("Defeat presentation requires this pack's locomotion and capture poses.")
	if boss_actions != null:
		_check_textures(effects, ["sack_open"], "boss props", errors)
		errors.append_array(boss_actions.validation_errors())
		for key in ["reach", "release", "hold", "air", "land"]:
			var texture: Texture2D = boss_action_frames.get(key)
			if texture == null or texture.get_size() != Vector2(512, 512):
				errors.append("Missing or misaligned boss action: " + key)
		var bounds: Rect2 = enemy_frame_bounds.get("boss", Rect2())
		if bounds.size.x <= 0 or bounds.size.y <= 0 or not Rect2(0, 0, 1, 1).encloses(bounds):
			errors.append("Invalid boss action reference bounds.")
	elif not boss_action_frames.is_empty():
		errors.append("Boss action frames require their own configuration.")
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

func _check_run_frames(key: String, expected_size: Vector2, errors: Array[String]) -> void:
	var frames: Array = run_frames.get(key, [])
	if frames.size() < 2:
		errors.append("Missing running sequence: " + key)
	var frame_size: Vector2 = expected_size
	for texture in frames:
		if not texture is Texture2D:
			errors.append("Invalid running texture: " + key)
		elif frame_size == Vector2.ZERO:
			frame_size = texture.get_size()
		elif texture.get_size() != frame_size:
			errors.append("Misaligned running frame dimensions: " + key)
