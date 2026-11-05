class_name ControlsConfig
extends Resource

@export_range(0.05, 0.9, 0.01) var stick_deadzone: float
## Distances use the 1280x800 logical canvas, independent of screen resolution.
@export_range(1.0, 100.0) var drag_threshold: float
@export_range(0.05, 1.0, 0.01) var tap_seconds: float
@export_range(20.0, 300.0) var ground_tap_height: float
