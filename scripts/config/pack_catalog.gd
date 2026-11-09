class_name PackCatalog
extends RefCounted
## Explicit installed presentation packs. Export tooling filters this same registry.
var entries: Array[Dictionary] = []
var default_id: String = ""
var errors: Array[String] = []

func _init(path: String = "res://config/pack_catalog.json") -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or value.get("schema") != 1 or not value.get("packs") is Array:
		errors.append("Invalid presentation catalog.")
		return
	default_id = str(value.get("default_pack", ""))
	var seen: Array[String] = []
	for entry in value.packs:
		if not entry is Dictionary or not entry.has_all(["id", "name", "description", "path", "preview"]):
			errors.append("Incomplete catalog entry.")
			continue
		var id: String = str(entry.id)
		if id.is_empty() or id in seen or entry.path != "res://assets/packs/" + id + "/pack.tres" or not str(entry.preview).begins_with("res://assets/packs/" + id + "/"):
			errors.append("Invalid or duplicate catalog pack: " + id)
			continue
		seen.append(id)
		if not ResourceLoader.exists(entry.path) or not ResourceLoader.exists(entry.preview):
			errors.append("Missing installed pack: " + id)
		entries.append(entry)
	if not has_pack(default_id): errors.append("Catalog requires an installed default pack.")

func has_pack(id: String) -> bool:
	return not entry_for(id).is_empty()

func entry_for(id: String) -> Dictionary:
	for entry in entries:
		if entry.id == id: return entry
	return {}

func resolve(id: String) -> String:
	return id if has_pack(id) else default_id

func load_pack(id: String) -> AssetPack:
	var entry := entry_for(id)
	if entry.is_empty(): return null
	var pack := load(entry.path) as AssetPack
	if pack == null or str(pack.pack_id) != id or not pack.validation_errors().is_empty():
		return null
	return pack
