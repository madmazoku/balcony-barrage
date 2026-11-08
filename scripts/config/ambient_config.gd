class_name AmbientConfig
extends Resource
## Background presentation only. All dimensions are defined by this resource pack.
@export var enabled: bool = true
@export var source_size: Vector2
@export var segments: int = 16
@export var layer_ids: PackedStringArray
@export var layer_rects: Dictionary[String, Rect2]
@export var periods: Dictionary[String, float]
@export var amplitudes: Dictionary[String, Vector2]
@export var turns: Dictionary[String, float]
@export var phases: Dictionary[String, float]

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if source_size.x <= 0 or source_size.y <= 0 or segments < 2 or segments > 64 or layer_ids.is_empty():
		errors.append("Ambient presentation requires a canvas, layers and 2..64 segments.")
	var seen: Dictionary = {}
	for id in layer_ids:
		if id.is_empty() or seen.has(id):
			errors.append("Ambient layer IDs must be nonempty and unique.")
		seen[id] = true
		var area: Rect2 = layer_rects.get(id, Rect2())
		if area.size.x <= 0 or area.size.y <= 0 or not Rect2(0, 0, 1, 1).encloses(area):
			errors.append("Invalid ambient layer rectangle: " + id)
		if periods.get(id, 0.0) <= 0 or turns.get(id, 0.0) <= 0:
			errors.append("Ambient periods and wave turns must be positive: " + id)
		if not amplitudes.has(id) or amplitudes[id].x < 0 or amplitudes[id].y < 0:
			errors.append("Invalid ambient sway: " + id)
		if not phases.has(id) or phases[id] < 0 or phases[id] >= 1:
			errors.append("Ambient phase must be inside [0,1): " + id)
	return errors
