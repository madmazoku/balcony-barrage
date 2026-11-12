class_name PlatformMotion
extends RefCounted

var settings: PlatformMotionConfig
var sections: Array[Texture2D]
var debris_atlas: Texture2D
var debris_origins: PackedVector2Array
var age: float = -1.0
var collapsed: bool = false
var first_section: int = 0
var bursts: Array[Dictionary] = []

func _init(config: PlatformMotionConfig, pack: AssetPack) -> void:
	settings = config
	var left := pack.environment.get("balcony_collapse_left") as Texture2D
	var right := pack.environment.get("balcony_collapse_right") as Texture2D
	if left != null and right != null:
		sections.assign([left, right])
	debris_atlas = pack.effects.get("platform_debris") as Texture2D
	debris_origins = pack.platform_debris_origins

func clear() -> void:
	age = -1.0
	collapsed = false
	first_section = 0
	bursts.clear()

func impact(previous: int, stage: int, landing_x: float) -> void:
	age = 0.0
	collapsed = stage == 5
	if not sections.is_empty():
		first_section = 0 if landing_x < _section_split() else 1
	if debris_atlas != null:
		for index in range(previous, stage):
			bursts.append({"age": 0.0, "origin": debris_origins[index], "stage": index})

func advance(delta: float) -> void:
	if age >= 0.0:
		age += delta
	for burst in bursts:
		burst.age += delta
	bursts = bursts.filter(func(burst: Dictionary) -> bool: return burst.age < settings.debris_seconds)

func sag() -> float:
	if sections.is_empty() or collapsed or age < 0.0 or age >= settings.sag_seconds:
		return 0.0
	var phase: float = age / settings.sag_seconds
	return settings.sag_pixels * sin(PI * phase) * (1.0 - phase)

func section_pose(section: int) -> Transform2D:
	var time: float = maxf(0.0, age - (0.0 if section == first_section else settings.section_delay))
	var fall_time: float = maxf(0.0, time - settings.hinge_seconds)
	var hinge: float = deg_to_rad(settings.hinge_degrees) * smoothstep(0.0, settings.hinge_seconds, time)
	var spin: float = deg_to_rad(settings.fall_spin_degrees) * fall_time
	var drop: float = settings.fall_speed * fall_time + 0.5 * settings.fall_gravity * fall_time * fall_time
	return Transform2D((hinge + spin) * (1.0 if section == 0 else -1.0), Vector2(0.0, drop))

func paint(canvas: Node2D, bounds: Rect2, texture: Texture2D) -> void:
	if not collapsed or sections.is_empty():
		canvas.draw_texture_rect(texture, Rect2(bounds.position + Vector2(0.0, sag()), bounds.size), false)
	elif age < settings.collapse_seconds:
		_paint_sections(canvas, bounds)
	if not bursts.is_empty():
		_paint_debris(canvas, bounds)

func _section_split() -> float:
	return float(sections[0].get_width()) / (sections[0].get_width() + sections[1].get_width())

func _paint_sections(canvas: Node2D, bounds: Rect2) -> void:
	var left_width: float = bounds.size.x * _section_split()
	for section in 2:
		var pose: Transform2D = section_pose(section)
		var pivot: Vector2 = bounds.position + Vector2(bounds.size.x * section, 0.0)
		var target := Rect2(0.0, 0.0, left_width, bounds.size.y) if section == 0 else \
			Rect2(left_width - bounds.size.x, 0.0, bounds.size.x - left_width, bounds.size.y)
		canvas.draw_set_transform(pivot + pose.origin, pose.get_rotation())
		canvas.draw_texture_rect(sections[section], target, false)
	canvas.draw_set_transform(Vector2.ZERO)

func _paint_debris(canvas: Node2D, bounds: Rect2) -> void:
	var tile: float = debris_atlas.get_height()
	for burst in bursts:
		var time: float = burst.age
		var origin: Vector2 = bounds.position + bounds.size * burst.origin
		var opacity: float = 1.0 - smoothstep(settings.debris_seconds * 0.55, settings.debris_seconds, time)
		for index in settings.debris_count:
			var spread: float = float(index) / (settings.debris_count - 1)
			var side: float = 1.0 if index % 2 == 0 else -1.0
			var velocity: Vector2 = settings.debris_velocity * Vector2(spread * 2.0 - 1.0, 0.45 + fmod(index * 0.37, 0.55))
			var start: Vector2 = origin + Vector2((spread - 0.5) * bounds.size.x * 0.09, fmod(index * 3.8, 16.0))
			var position: Vector2 = start + velocity * time + Vector2(sin(time * 8.0 + index) * time * 13.0,
				0.5 * settings.debris_gravity * time * time)
			var size: float = lerpf(settings.debris_size.x, settings.debris_size.y, fmod(index * 0.41, 1.0))
			var region := Rect2(tile * ((index + int(burst.stage)) % 3), 0.0, tile, tile)
			canvas.draw_set_transform(position, index * 2.4 + side * time * 5.5)
			canvas.draw_texture_rect_region(debris_atlas, Rect2(-Vector2.ONE * size / 2.0, Vector2.ONE * size),
				region, Color(1.0, 1.0, 1.0, opacity))
	canvas.draw_set_transform(Vector2.ZERO)
