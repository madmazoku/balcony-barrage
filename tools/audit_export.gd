extends SceneTree
## Run from an empty temporary project: the source tree must not mask missing files.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not ProjectSettings.load_resource_pack(args[0], true):
		push_error("Cannot open exported resource pack.")
		quit(1)
		return
	var expected: PackedStringArray = args[1].split(",", false)
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/pack_catalog.json"))
	var found: Array[String] = []
	for id in DirAccess.get_directories_at("res://assets/packs"):
		if id not in expected:
			push_error("Excluded pack found in export: " + id)
			quit(1)
			return
		found.append(id)
	var listed: Array[String] = []
	if catalog is Dictionary:
		for entry in catalog.get("packs", []): listed.append(entry.id)
	found.sort()
	listed.sort()
	var ordered: Array[String] = []
	ordered.assign(expected)
	ordered.sort()
	if found != ordered or listed != ordered or not str(catalog.get("default_pack", "")) in ordered:
		push_error("Exported content/catalog does not match the selected profile.")
		quit(1)
		return
	print("EXPORTED_CONTENT_OK " + ",".join(found))
	quit()
