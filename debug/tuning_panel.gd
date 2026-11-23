extends CanvasLayer
## In-game tuning panel. Tab or the View button opens it and pauses the game.
## Shows a slider for every number in the car's setup, grouped like the setup file.
## Changes apply at once; Save writes them to save_path and closes the panel.
## Clicking outside the panel closes it too.
## Closing with unsaved changes asks first: save, keep driving on them unsaved, or undo them.

@export var car: Car
## The AI driver, for its skill slider. That slider changes the AI only and is never saved.
@export var ai: AiDriver
## The learning level, for the Level row at the top. Kept in its own file, not the setup.
@export var level: LearningLevel
## Where Save writes the setup and Revert reads it back from.
@export_file("*.tres") var save_path := "res://car/roadster.tres"

var _sliders := {}  # Property name to HSlider.
var _toggles := {}  # Property name to CheckButton, for on/off settings.
var _saved := {}  # Property name to its value in the saved file.
var _values := {}  # Property name to its value Label.
var _status: Label
var _ai_slider: HSlider
var _ai_value: Label
var _level_slider: HSlider
var _level_value: Label
var _first_slider: HSlider
var _panel: PanelContainer
var _confirm: PanelContainer
var _confirm_text: Label
var _confirm_first: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	_build_confirm()
	_panel.visible = false
	_confirm.visible = false
	_remember_saved()


# _input, not _unhandled_input: while a slider has focus, Godot's GUI uses Tab to move
# focus and would swallow it before _unhandled_input sees it.
func _input(event: InputEvent) -> void:
	if _confirm.visible and (event.is_action_pressed("tune_panel") or event.is_action_pressed("ui_cancel")):
		back_to_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tune_panel"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _panel.visible and _is_click_outside(event):
		toggle()
		get_viewport().set_input_as_handled()


func _is_click_outside(event: InputEvent) -> bool:
	var click := event as InputEventMouseButton
	return click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT \
			and not _panel.get_global_rect().has_point(click.position)


## Opens the panel, or closes it. With unsaved changes, closing asks first.
func toggle() -> void:
	if not is_open():
		_panel.visible = true
		get_tree().paused = true
		refresh()
		_status.text = ""
		_first_slider.grab_focus.call_deferred()
	elif has_unsaved_changes():
		_ask_before_closing()
	else:
		close()


## Closes without asking. Unsaved changes stay on the car.
func close() -> void:
	_panel.visible = false
	_confirm.visible = false
	get_tree().paused = false


func is_open() -> bool:
	return _panel.visible or _confirm.visible


func is_asking() -> bool:
	return _confirm.visible


## Leaves the unsaved-changes question and goes back to the sliders.
func back_to_panel() -> void:
	_confirm.visible = false
	_panel.visible = true
	_first_slider.grab_focus.call_deferred()


## Settings that differ from the saved file.
func unsaved_changes() -> PackedStringArray:
	var changed := PackedStringArray()
	for property in _saved:
		var now = car.setup.get(property)
		var was = _saved[property]
		if typeof(now) == TYPE_BOOL and now != was or typeof(now) == TYPE_FLOAT and not is_equal_approx(now, was):
			changed.append(property)
	return changed


func has_unsaved_changes() -> bool:
	return not unsaved_changes().is_empty()


## Sets one setup value as if its slider or switch moved.
func set_value(property: String, value: Variant) -> void:
	if _toggles.has(property):
		_toggles[property].button_pressed = value
	else:
		_sliders[property].value = value


## Writes the setup to save_path. Returns the Godot error code.
func save() -> Error:
	var err := ResourceSaver.save(car.setup, save_path)
	if err == OK:
		_remember_saved()
	_status.text = "Saved to %s" % save_path if err == OK else "Save failed: %s" % error_string(err)
	return err


## Throws away unsaved changes: reads save_path again and copies its values into the car.
func revert() -> Error:
	var saved := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as CarSetup
	if saved == null:
		_status.text = "Could not read %s" % save_path
		return ERR_CANT_OPEN
	for property in _saved:
		car.setup.set(property, saved.get(property))
	car.apply_setup()
	_remember_saved()
	refresh()
	_status.text = "Reverted to %s" % save_path
	return OK


## Moves every slider to the car's current value.
func refresh() -> void:
	for property in _sliders:
		_sliders[property].set_value_no_signal(car.setup.get(property))
		_show_value(property)
	for property in _toggles:
		_toggles[property].set_pressed_no_signal(car.setup.get(property))
	if _level_slider != null:
		_level_slider.set_value_no_signal(level.level)
		_level_value.text = level.level_name()
	if _ai_slider != null:
		_ai_slider.set_value_no_signal(ai.skill)
		_ai_value.text = "%d %%" % ai.skill


func _remember_saved() -> void:
	_saved.clear()
	for property in _sliders.keys() + _toggles.keys():
		_saved[property] = car.setup.get(property)


func _ask_before_closing() -> void:
	var changed := unsaved_changes()
	var names := PackedStringArray()
	for property in changed:
		names.append(property.capitalize())
	_confirm_text.text = "Unsaved changes: %s.\nB or Tab goes back to the setup." % ", ".join(names)
	_panel.visible = false
	_confirm.visible = true
	_confirm_first.grab_focus.call_deferred()


func _save_and_close() -> void:
	if save() == OK:
		close()
	else:
		back_to_panel()


func _undo_and_close() -> void:
	if revert() == OK:
		close()
	else:
		back_to_panel()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -620.0
	_panel.offset_right = -16.0
	_panel.offset_top = 16.0
	_panel.offset_bottom = -16.0
	add_child(_panel)

	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	var title := Label.new()
	title.text = "Car setup   (Tab or View to close, D-pad to move and change, A to switch on/off)"
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	outer.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	if level != null:
		var level_header := Label.new()
		level_header.text = "Learning level (Noob gives the most help)"
		level_header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		rows.add_child(level_header)
		rows.add_child(_make_level_row())

	for info in car.setup.get_property_list():
		if info.usage & PROPERTY_USAGE_GROUP:
			var header := Label.new()
			header.text = info.name
			header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
			rows.add_child(header)
		elif info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and info.type == TYPE_FLOAT \
				and info.hint == PROPERTY_HINT_RANGE:
			rows.add_child(_make_row(info.name, info.hint_string))
		elif info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and info.type == TYPE_BOOL:
			rows.add_child(_make_toggle(info.name))
	if ai != null:
		var header := Label.new()
		header.text = "AI driver (not saved)"
		header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		rows.add_child(header)
		rows.add_child(_make_ai_row())

	var buttons := HBoxContainer.new()
	outer.add_child(buttons)
	for pair in [["Save", _save_and_close], ["Revert", revert], ["Close", toggle]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(pair[1])
		buttons.add_child(button)
	_status = Label.new()
	outer.add_child(_status)


## Centred box asking what to do with unsaved changes. Shown in place of the panel.
func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_confirm)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_confirm.add_child(box)
	_confirm_text = Label.new()
	_confirm_text.custom_minimum_size.x = 560.0
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_confirm_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	for pair in [["Save", _save_and_close], ["Drive without saving", close],
			["Undo changes", _undo_and_close], ["Back", back_to_panel]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(pair[1])
		buttons.add_child(button)
		if _confirm_first == null:
			_confirm_first = button


func _make_toggle(property: String) -> Control:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = property.capitalize()
	name_label.custom_minimum_size.x = 260.0
	row.add_child(name_label)
	var toggle_button := CheckButton.new()
	toggle_button.button_pressed = car.setup.get(property)
	toggle_button.toggled.connect(_on_toggled.bind(property))
	row.add_child(toggle_button)
	_toggles[property] = toggle_button
	return row


func _on_toggled(pressed: bool, property: String) -> void:
	car.setup.set(property, pressed)
	car.apply_setup()


func _make_row(property: String, hint: String) -> Control:
	var parts := hint.split(",")
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = property.capitalize()
	name_label.custom_minimum_size.x = 260.0
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = float(parts[0])
	slider.max_value = float(parts[1])
	slider.step = float(parts[2]) if parts.size() > 2 else 0.0
	slider.gui_input.connect(_on_slider_input.bind(slider))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = car.setup.get(property)
	slider.value_changed.connect(_on_slider_changed.bind(property))
	row.add_child(slider)
	if _first_slider == null:
		_first_slider = slider

	var value_label := Label.new()
	value_label.custom_minimum_size.x = 100.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	_sliders[property] = slider
	_values[property] = value_label
	_show_value(property)
	return row


## Slider for the learning level, Noob to Expert. Kept apart from the setup sliders so Save
## and the unsaved-changes question never see it. The level saves itself.
func _make_level_row() -> Control:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Level"
	name_label.custom_minimum_size.x = 260.0
	row.add_child(name_label)
	_level_slider = HSlider.new()
	_level_slider.min_value = 0.0
	_level_slider.max_value = LearningLevel.NAMES.size() - 1
	_level_slider.step = 1.0
	_level_slider.tick_count = LearningLevel.NAMES.size()
	_level_slider.ticks_on_borders = true
	_level_slider.gui_input.connect(_on_slider_input.bind(_level_slider))
	_level_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_level_slider.value = level.level
	row.add_child(_level_slider)
	_level_value = Label.new()
	_level_value.custom_minimum_size.x = 120.0
	_level_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level_value.text = level.level_name()
	row.add_child(_level_value)
	_level_slider.value_changed.connect(func(value: float) -> void:
		level.set_level(int(value))
		refresh())  # The AI's skill follows the level.
	_first_slider = _level_slider
	return row


## Slider for the AI's skill. Kept apart from the setup sliders so Save and the
## unsaved-changes question never see it.
func _make_ai_row() -> Control:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Skill"
	name_label.custom_minimum_size.x = 260.0
	row.add_child(name_label)
	_ai_slider = HSlider.new()
	_ai_slider.min_value = 30.0
	_ai_slider.max_value = 100.0
	_ai_slider.step = 1.0
	_ai_slider.gui_input.connect(_on_slider_input.bind(_ai_slider))
	_ai_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ai_slider.value = ai.skill
	row.add_child(_ai_slider)
	_ai_value = Label.new()
	_ai_value.custom_minimum_size.x = 100.0
	_ai_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ai_value.text = "%d %%" % ai.skill
	row.add_child(_ai_value)
	_ai_slider.value_changed.connect(func(value: float) -> void:
		ai.skill = value
		_ai_value.text = "%d %%" % value)
	return row


## One D-pad or arrow press moves 1 % of the range, rounded to the slider's step.
func _on_slider_input(event: InputEvent, slider: HSlider) -> void:
	var direction := 0.0
	if event.is_action_pressed("ui_right", true):
		direction = 1.0
	elif event.is_action_pressed("ui_left", true):
		direction = -1.0
	if direction == 0.0:
		return
	var nudge := maxf(slider.step, snappedf((slider.max_value - slider.min_value) / 100.0, slider.step))
	slider.value += direction * nudge
	slider.accept_event()


func _on_slider_changed(value: float, property: String) -> void:
	car.setup.set(property, value)
	car.apply_setup()
	_show_value(property)


func _show_value(property: String) -> void:
	var step: float = _sliders[property].step
	var decimals := 0 if step >= 1.0 or step <= 0.0 else str(step).split(".")[1].length()
	_values[property].text = String.num(car.setup.get(property), decimals)
