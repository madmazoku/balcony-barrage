class_name GameplayConfig
extends Resource
## Units are pixels and seconds. Authoritative values live in gameplay.tres.
@export_group("Player")
@export_range(1.0, 2000.0) var player_speed: float
@export_range(1.0, 4000.0) var bolt_speed: float
@export_range(0.01, 5.0) var shot_cooldown: float
@export_range(0, 10) var armor_parts: int
@export_range(0.01, 5.0) var damage_grace_seconds: float
@export_group("Minions")
@export_range(1, 10) var normal_balloons: int
@export_range(1, 10) var tank_balloons: int
@export_range(1, 10) var thrower_balloons: int
@export_range(1.0, 500.0) var descent_speed: float
@export_range(1.0, 1000.0) var ground_speed: float
@export_range(0.0, 300.0) var wind_amplitude: float
@export_range(0.01, 10.0) var wind_period_seconds: float
@export_range(0.1, 20.0) var nut_interval_seconds: float
@export_range(0.01, 5.0) var nut_windup_seconds: float
@export_range(1.0, 2000.0) var nut_speed: float
@export_group("Wave")
@export var random_seed: int
## Parallel arrays: release offset in seconds and normal/tank/thrower role.
@export var release_times: PackedFloat32Array
@export var release_roles: PackedStringArray
@export_group("Boss")
@export_range(1.0, 1000.0) var boss_speed: float
@export_range(1, 20) var balcony_stages: int
@export_range(0.01, 5.0) var boss_jump_seconds: float
@export var furniture_enabled: bool
@export_range(0.1, 20.0) var furniture_interval_seconds: float
@export_range(0.01, 5.0) var furniture_windup_seconds: float
@export_range(1.0, 2000.0) var furniture_speed: float
@export_range(1.0, 300.0) var furniture_hit_width: float
