class_name ProjectileTrail
extends RefCounted
## Read-only references to live shots; no model keys, RNG or independent collisions.
var settings: ProjectileVisualConfig
var records: Array[Dictionary] = []

func _init(config: ProjectileVisualConfig) -> void:
	settings = config

func clear() -> void:
	records.clear()

func _record(bolt: Dictionary) -> Dictionary:
	for record in records:
		if is_same(record.bolt, bolt):
			return record
	return {}

func track(bolt: Dictionary) -> void:
	if settings.enabled and _record(bolt).is_empty():
		records.append({"bolt": bolt, "origin": bolt.pos, "age": 0.0})

func advance(bolts: Array[Dictionary], delta: float) -> void:
	# A consumed shot loses its entire trail immediately, rather than leaving a fake projectile.
	records = records.filter(func(record: Dictionary) -> bool:
		return bolts.any(func(bolt: Dictionary) -> bool: return is_same(bolt, record.bolt)))
	for record in records:
		record.age += delta
	for bolt in bolts:
		track(bolt)

func pose(bolt: Dictionary, size: Vector2) -> Dictionary:
	var result: Dictionary = {"trail": [], "head_tint": Color.WHITE}
	var record: Dictionary = _record(bolt)
	if not settings.enabled or record.is_empty():
		return result
	var length: float = minf(settings.trail_length, (bolt.pos as Vector2).distance_to(record.origin))
	if length > 0:
		for index in range(settings.trail_samples, 0, -1):
			var fraction: float = float(index) / (settings.trail_samples + 1)
			var scale: float = lerpf(1.0, settings.tail_scale, fraction)
			var tint: Color = settings.trail_tint
			tint.a *= settings.trail_opacity * (1 - fraction) * (1 - fraction)
			result.trail.append({"offset": length * fraction, "size": size * scale, "tint": tint})
	var glint: float = pow(maxf(0.0, cos(TAU * record.age / settings.glint_period)), settings.glint_power) * settings.glint_strength
	result.head_tint = Color(1 + glint * settings.glint_tint.r, 1 + glint * settings.glint_tint.g, 1 + glint * settings.glint_tint.b, 1)
	return result
