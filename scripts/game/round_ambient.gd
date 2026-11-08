class_name RoundAmbient
extends RefCounted
## Smoothly deforms generated leaf pixels. No model reference or random state.
var settings: AmbientConfig
var arena: Vector2
var phases: Dictionary[String, float] = {}
var meshes: Dictionary[String, ArrayMesh] = {}

func _init(config: AmbientConfig, arena_size: Vector2) -> void:
	settings = config
	arena = arena_size
	for id in settings.layer_ids:
		meshes[id] = ArrayMesh.new()
	reset()

func reset() -> void:
	for id in settings.layer_ids:
		phases[id] = settings.phases[id]
		_update_mesh(id)

func advance(delta: float) -> void:
	if not settings.enabled:
		return
	for id in settings.layer_ids:
		phases[id] = fposmod(phases[id] + delta / settings.periods[id], 1.0)
		_update_mesh(id)

func _update_mesh(id: String) -> void:
	var area: Rect2 = settings.layer_rects[id]
	var amplitude: Vector2 = settings.amplitudes[id] * arena / settings.source_size
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in settings.segments + 1:
		var v: float = float(row) / settings.segments
		# Pin both ends, including the pieces adjacent to the stone cornice.
		var weight: float = pow(sin(PI * v), 2)
		var wave: float = TAU * (phases[id] - v * settings.turns[id])
		var shift := Vector2(sin(wave) * amplitude.x, cos(wave) * amplitude.y) * weight
		for column in 2:
			var uv := Vector2(column, v)
			var position: Vector2 = (area.position + uv * area.size) * arena + shift
			vertices.append(Vector3(position.x, position.y, 0))
			uvs.append(uv)
		if row < settings.segments:
			var first: int = row * 2
			indices.append_array(PackedInt32Array([first, first + 2, first + 1, first + 1, first + 2, first + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	meshes[id].clear_surfaces()
	meshes[id].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
