class_name TrackMenu
extends Control
## First screen: pick a track, then the game starts on it.
## Works with the mouse, the keyboard (arrows and Enter) or a gamepad (stick and A).

const MAIN_SCENE := "res://main.tscn"
const TRACKS := [
	{"name": "Practice track", "about": "Short hill circuit. Good for learning.",
			"scene": "res://track/ridge/ridge.tscn"},
	{"name": "Clarion loop", "about": "Real roads round Clarion, PA: Route 68, I-80, Route 66 and Route 322. 17 km a lap.",
			"scene": "res://track/clarion/clarion.tscn"},
]

@onready var _buttons: VBoxContainer = %Buttons
@onready var _loading: Label = %Loading


func _ready() -> void:
	for entry in TRACKS:
		var button := Button.new()
		button.text = "%s\n%s" % [entry.name, entry.about]
		button.custom_minimum_size = Vector2(760, 120)
		button.add_theme_font_size_override("font_size", 30)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_stylebox_override("focus", _focus_box())
		button.pressed.connect(_start.bind(entry.scene))
		_buttons.add_child(button)
	(_buttons.get_child(0) as Button).grab_focus.call_deferred()


func _start(track_scene: String) -> void:
	for button in _buttons.get_children():
		button.disabled = true
	_loading.show()
	# Let "Loading…" show before the big track build stops the screen for a moment.
	await get_tree().process_frame
	await get_tree().process_frame
	Main.track_scene = load(track_scene)
	var main: Node = load(MAIN_SCENE).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	queue_free()


## A thick yellow frame, so it is easy to see which track Enter or A will pick.
func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = Color(1.0, 0.8, 0.2)
	box.set_border_width_all(5)
	box.set_corner_radius_all(4)
	return box
