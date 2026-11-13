class_name ShellStyle
extends Resource
## Interface appearance and copy travel with the selected presentation pack.
@export var title: String = "BALCONY BARRAGE"
@export var subtitle: String = "Удержи двор. Опустоши мешок. Обрушь балкон."
@export var panel: Color = Color("241a16")
@export var border: Color = Color("9d784a")
@export var accent: Color = Color("eac37d")
@export var text: Color = Color("fff2d8")
@export var muted: Color = Color("cdbba1")
@export var button: Color = Color("443326")
@export var dim: Color = Color(0.025, 0.018, 0.012, 0.68)
@export var panel_width: float = 680
@export var heading_size: int = 38
@export var body_size: int = 22
@export var button_height: float = 54
@export var round_text: Dictionary[String, String] = {}

func text_for(key: String, default_text: String) -> String:
	return round_text.get(key, default_text)

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if title.is_empty() or panel_width <= 0 or heading_size <= 0 or body_size <= 0 or button_height <= 0:
		errors.append("Menu style requires a title and positive layout dimensions.")
	return errors
