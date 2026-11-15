extends CanvasLayer

var mission_panel: PanelContainer
var mission_label: Label
var mission_status: Label
var dialogue_panel: PanelContainer
var speaker_label: Label
var message_label: Label
var actions: HBoxContainer
var arrow: Node2D
var player: CharacterBody2D
var mission_target: Node2D
var buttons: Array[Button] = []
var choice_value := false
var choice_completed := false


func _ready() -> void:
	layer = 10
	player = get_parent().find_child("CharacterBody2d", true, false) as CharacterBody2D
	_build_mission_panel()
	_build_dialogue_panel()
	arrow = _ArrowIndicator.new()
	arrow.z_index = -1
	add_child(arrow)
	get_viewport().size_changed.connect(_layout_dialogue_panel)
	_layout_dialogue_panel()


func set_mission(text: String, target: Node2D = null) -> void:
	mission_label.text = text
	mission_target = target
	mission_status.text = "OBJECTIVE"
	_update_indicator()


func say(speaker: String, message: String, duration: float = 3.0) -> void:
	_clear_buttons()
	speaker_label.text = speaker
	message_label.text = message
	dialogue_panel.show()
	if duration > 0.0:
		var display_time := maxf(duration, minf(7.0, message.length() * 0.055))
		await get_tree().create_timer(display_time).timeout
		dialogue_panel.hide()


func choose(speaker: String, message: String, first_choice: String, second_choice: String) -> bool:
	speaker_label.text = speaker
	message_label.text = message
	choice_completed = false
	_add_choice_button(first_choice, true)
	_add_choice_button(second_choice, false)
	dialogue_panel.show()
	while not choice_completed:
		await get_tree().process_frame
	dialogue_panel.hide()
	_clear_buttons()
	return choice_value


func hide_dialogue() -> void:
	dialogue_panel.hide()


func _build_mission_panel() -> void:
	mission_panel = PanelContainer.new()
	mission_panel.position = Vector2(24, 22)
	mission_panel.custom_minimum_size = Vector2(370, 126)
	mission_panel.add_theme_stylebox_override("panel", _panel_style(Color("10213de8"), Color("59c8ed")))
	add_child(mission_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	mission_panel.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 9)
	layout.add_child(header)

	var marker := Label.new()
	marker.text = "◆"
	marker.add_theme_color_override("font_color", Color("71dcff"))
	marker.add_theme_font_size_override("font_size", 18)
	header.add_child(marker)

	var title := Label.new()
	title.text = "MISSION OBJECTIVE"
	title.add_theme_color_override("font_color", Color("71dcff"))
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	mission_status = Label.new()
	mission_status.text = "OBJECTIVE"
	mission_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mission_status.add_theme_color_override("font_color", Color("f5cb69"))
	mission_status.add_theme_font_size_override("font_size", 12)
	header.add_child(mission_status)

	mission_label = Label.new()
	mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_label.custom_minimum_size = Vector2(330, 54)
	mission_label.add_theme_color_override("font_color", Color("f4f7ff"))
	mission_label.add_theme_font_size_override("font_size", 18)
	layout.add_child(mission_label)


func _build_dialogue_panel() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.custom_minimum_size = Vector2(760, 205)
	dialogue_panel.add_theme_stylebox_override("panel", _panel_style(Color("101a2bf2"), Color("71dcff")))
	add_child(dialogue_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	dialogue_panel.add_child(layout)

	speaker_label = Label.new()
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.add_theme_color_override("font_color", Color("71dcff"))
	speaker_label.add_theme_font_size_override("font_size", 20)
	layout.add_child(speaker_label)

	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color("426179"))
	layout.add_child(separator)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(710, 82)
	message_label.add_theme_color_override("font_color", Color("f4f7ff"))
	message_label.add_theme_font_size_override("font_size", 18)
	layout.add_child(message_label)

	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	layout.add_child(actions)
	dialogue_panel.hide()


func _layout_dialogue_panel() -> void:
	if not is_instance_valid(dialogue_panel):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	dialogue_panel.size = Vector2(minf(760.0, viewport_size.x - 32.0), 205.0)
	dialogue_panel.position = Vector2(
		(viewport_size.x - dialogue_panel.size.x) / 2.0,
		viewport_size.y - dialogue_panel.size.y - 22.0
	)


func _process(_delta: float) -> void:
	_update_indicator()


func _update_indicator() -> void:
	if not is_instance_valid(player) or not is_instance_valid(mission_target):
		mission_status.text = "OBJECTIVE"
		arrow.visible = false
		return
	var world_direction := mission_target.global_position - player.global_position
	mission_status.text = "AREA REACHED" if world_direction.length() < 90.0 else "IN PROGRESS"
	var screen_direction := (
		mission_target.get_global_transform_with_canvas().origin
		- player.get_global_transform_with_canvas().origin
	)
	if screen_direction.length_squared() < 1.0:
		arrow.visible = false
		return
	arrow.position = player.get_global_transform_with_canvas().origin + screen_direction.normalized() * 38.0
	arrow.rotation = screen_direction.angle()
	arrow.visible = world_direction.length() >= 45.0


func _add_choice_button(text: String, value: bool) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 42)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(_on_choice_pressed.bind(value))
	actions.add_child(button)
	buttons.append(button)


func _on_choice_pressed(value: bool) -> void:
	choice_value = value
	choice_completed = true


func _clear_buttons() -> void:
	for button in buttons:
		button.queue_free()
	buttons.clear()


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 6
	return style


class _ArrowIndicator:
	extends Node2D

	func _draw() -> void:
		var outline := PackedVector2Array([
			Vector2(19, 0), Vector2(3, -11), Vector2(5, -4),
			Vector2(-14, -4), Vector2(-14, 4), Vector2(5, 4),
			Vector2(3, 11)
		])
		var fill := PackedVector2Array([
			Vector2(15, 0), Vector2(3, -7), Vector2(4, -2),
			Vector2(-10, -2), Vector2(-10, 2), Vector2(4, 2),
			Vector2(3, 7)
		])
		draw_colored_polygon(outline, Color("101a2b"))
		draw_colored_polygon(fill, Color("ffd66b"))
