class_name GameplayConfig
extends Resource
@export_group("Arena")
@export var arena_size: Vector2
@export var ground_y: float
@export var boss_y: float
@export var balcony_y: float
@export var balcony_left: float
@export var balcony_right: float
@export var spawn_drop: float
@export var player_size: Vector2
@export var boss_size: Vector2
@export var normal_size: Vector2
@export var tank_size: Vector2
@export var thrower_size: Vector2
@export var bolt_size: Vector2
@export var nut_size: Vector2
@export var furniture_height: float
@export var balloon_radius: float
@export var balloon_spacing: float
@export var balloon_lift: float
@export var escape_speed: float
@export var fall_speed: float
@export var boss_jump_height: float
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
## Half-angle of the downward aiming cone, in degrees.
@export_range(0.0, 80.0, 1.0) var nut_max_angle_degrees: float
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
