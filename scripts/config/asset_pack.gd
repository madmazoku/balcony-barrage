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
