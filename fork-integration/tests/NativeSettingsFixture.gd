extends Node
const Paths = preload("res://src/save/Paths.gd")
var settings: Dictionary = {}
var settings_m: Dictionary = {}
var reloads := 0
var saves := 0
func provider_(_name: String) -> Dictionary: return settings.providers.brain
func _load_it() -> void:
	reloads += 1; settings = Paths.settings()
func save_it() -> void:
	saves += 1; Paths.fixture = settings.duplicate(true)
func _card() -> PanelContainer:
	var panel := PanelContainer.new(); panel.add_child(VBoxContainer.new()); return panel
func _button(text: String) -> Button:
	var value := Button.new(); value.text = text; value.set_meta("native_fixture",true); return value
func _text(text: String) -> Label:
	var value := Label.new(); value.text = text; value.set_meta("native_fixture",true); return value
