extends CanvasLayer

const SENSITIVITY_MIN: float = 0.25
const SENSITIVITY_MAX: float = 5.0

var pause_overlay: Control
var resume_button: Button
var sensitivity_value_label: Label

@onready var camera_controller: Node = get_parent().get_node("Camera")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_menu()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("start_button") and not event.is_echo():
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event.is_action_pressed("ui_cancel"):
		_resume_game()
		get_viewport().set_input_as_handled()


func _build_pause_menu() -> void:
	pause_overlay = Control.new()
	pause_overlay.name = "PauseMenu"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.hide()
	add_child(pause_overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.025, 0.03, 0.84)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.075, 0.105, 0.11, 0.98)
	panel_style.border_color = Color(0.26, 0.56, 0.52, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 26)
	content.add_child(title)

	var section_title := Label.new()
	section_title.text = "CONTROLLER SETTINGS"
	section_title.add_theme_color_override("font_color", Color(0.43, 0.78, 0.71))
	section_title.add_theme_font_size_override("font_size", 13)
	content.add_child(section_title)

	var sensitivity_row := HBoxContainer.new()
	sensitivity_row.add_theme_constant_override("separation", 12)
	content.add_child(sensitivity_row)

	var sensitivity_label := Label.new()
	sensitivity_label.text = "Look sensitivity"
	sensitivity_label.custom_minimum_size.x = 132
	sensitivity_row.add_child(sensitivity_label)

	var sensitivity_slider := HSlider.new()
	sensitivity_slider.min_value = SENSITIVITY_MIN
	sensitivity_slider.max_value = SENSITIVITY_MAX
	sensitivity_slider.step = 0.05
	sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity_slider.value = float(camera_controller.get("controller_sensitivity"))
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	sensitivity_row.add_child(sensitivity_slider)

	sensitivity_value_label = Label.new()
	sensitivity_value_label.custom_minimum_size.x = 48
	sensitivity_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sensitivity_row.add_child(sensitivity_value_label)
	_on_sensitivity_changed(sensitivity_slider.value)

	var invert_toggle := CheckButton.new()
	invert_toggle.text = "Invert vertical aim"
	invert_toggle.button_pressed = bool(camera_controller.get("controller_invert_y"))
	invert_toggle.toggled.connect(_on_invert_toggled)
	content.add_child(invert_toggle)

	resume_button = Button.new()
	resume_button.text = "Resume"
	resume_button.custom_minimum_size.y = 42
	resume_button.pressed.connect(_resume_game)
	content.add_child(resume_button)


func _toggle_pause() -> void:
	if get_tree().paused:
		_resume_game()
	else:
		pause_overlay.show()
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		resume_button.grab_focus()


func _resume_game() -> void:
	get_tree().paused = false
	pause_overlay.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_sensitivity_changed(value: float) -> void:
	camera_controller.set("controller_sensitivity", value)
	sensitivity_value_label.text = "%.2fx" % value


func _on_invert_toggled(enabled: bool) -> void:
	camera_controller.set("controller_invert_y", enabled)


func _on_camera_model_view_changed(view: bool) -> void:
	visible = !view
	if view and get_tree().paused:
		_resume_game()
