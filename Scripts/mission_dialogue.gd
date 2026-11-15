extends CanvasLayer

var mission_panel: PanelContainer
var mission_label: Label
var mission_status: Label
var dialogue_panel: PanelContainer
var dialogue_layout: VBoxContainer
var speaker_label: Label
var message_label: Label
var advance_button: Button
var actions: HBoxContainer
var arrow: Node2D
var player: CharacterBody2D
var mission_target: Node2D
var interaction_hint: Label
var warning_panel: PanelContainer
var warning_label: Label
var storm_overlay: Control
var notification_label: Label
var information_panel: PanelContainer
var information_title: Label
var information_text: Label
var input_panel: PanelContainer
var input_title: Label
var input_prompt: Label
var input_line_edit: LineEdit
var input_error_label: Label
var input_submitted := false
var input_result := ""
var game_over_panel: PanelContainer
var game_over_detail: Label
var fade_overlay: ColorRect
var static_overlay: Control
var credits_panel: Control
var dialogue_generation := 0
var dialogue_waiting := false
var radiation_shelter_urgency := false
var indicator_initialized := false
var indicator_enabled := true
var game_over_visible := false
var buttons: Array[Button] = []
var choice_value := false
var choice_completed := false


func _ready() -> void:
	layer = 10
	player = get_parent().find_child("CharacterBody2d", true, false) as CharacterBody2D
	_build_mission_panel()
	_build_dialogue_panel()
	_build_interaction_hint()
	_build_warning_display()
	_build_notification()
	_build_information_panel()
	_build_input_panel()
	_build_game_over_panel()
	_build_screen_overlays()
	arrow = _ArrowIndicator.new()
	arrow.z_index = 20
	get_parent().add_child(arrow)
	get_viewport().size_changed.connect(_layout_dialogue_panel)
	_layout_dialogue_panel()


func set_mission(text: String, target: Node2D = null) -> void:
	mission_label.text = text
	mission_target = target
	indicator_initialized = false
	indicator_enabled = true
	mission_status.text = "OBJECTIVE"
	_update_indicator(1.0)


func say(speaker: String, message: String, duration: float = 3.0) -> void:
	_clear_buttons()
	speaker_label.text = speaker
	message_label.text = message
	dialogue_panel.show()
	_layout_dialogue_panel()
	if duration > 0.0:
		advance_button.text = "click to advance to next dialogue or wait"
	else:
		advance_button.text = "click to advance dialogue"
	advance_button.show()
	dialogue_generation += 1
	var current_generation := dialogue_generation
	dialogue_waiting = true
	if duration > 0.0:
		var display_time := maxf(duration, minf(7.0, message.length() * 0.055))
		get_tree().create_timer(display_time).timeout.connect(
			_finish_dialogue.bind(current_generation)
		)
	while dialogue_waiting and current_generation == dialogue_generation:
		await get_tree().process_frame
	if current_generation == dialogue_generation:
		dialogue_waiting = false
		dialogue_panel.hide()
		advance_button.hide()


func choose(
	speaker: String,
	message: String,
	first_choice: String,
	second_choice: String,
	buttons_on_top: bool = false
) -> bool:
	speaker_label.text = speaker
	message_label.text = message
	advance_button.hide()
	dialogue_waiting = false
	choice_completed = false
	_clear_buttons()
	_add_choice_button(first_choice, true)
	_add_choice_button(second_choice, false)
	if is_instance_valid(dialogue_layout) and is_instance_valid(actions) and is_instance_valid(message_label):
		if buttons_on_top and actions.get_index() > message_label.get_index():
			dialogue_layout.move_child(actions, message_label.get_index())
		elif not buttons_on_top and actions.get_index() < message_label.get_index():
			dialogue_layout.move_child(actions, message_label.get_index())
	dialogue_panel.show()
	_layout_dialogue_panel()
	while not choice_completed:
		await get_tree().process_frame
	dialogue_panel.hide()
	_clear_buttons()
	return choice_value


func hide_dialogue() -> void:
	dialogue_panel.hide()


func set_interaction_hint(text: String) -> void:
	interaction_hint.text = text
	interaction_hint.visible = not text.is_empty()


func notify_item(item_name: String) -> void:
	notification_label.text = "+1  %s" % item_name
	notification_label.show()
	var tween := create_tween()
	tween.tween_interval(1.7)
	tween.tween_property(notification_label, "modulate:a", 0.0, 0.35)
	await tween.finished
	notification_label.hide()
	notification_label.modulate.a = 1.0


func show_radiation_warning(inside_safety_building: bool = false) -> void:
	radiation_shelter_urgency = inside_safety_building
	storm_overlay.show()
	warning_panel.show()
	_play_warning_beep()
	_update_warning_countdown()


func clear_sandstorm() -> void:
	storm_overlay.hide()


func clear_radiation_warning() -> void:
	clear_sandstorm()
	warning_panel.hide()


func show_information(title: String, text: String) -> void:
	information_title.text = title
	information_text.text = text
	information_panel.show()
	while information_panel.visible:
		await get_tree().process_frame


func prompt_text(title_text: String, prompt_message: String, placeholder: String = "Enter name...") -> String:
	input_title.text = title_text
	input_prompt.text = prompt_message
	input_line_edit.placeholder_text = placeholder
	input_line_edit.text = ""
	input_error_label.hide()
	input_submitted = false
	input_result = ""
	input_panel.show()
	_layout_dialogue_panel()
	input_line_edit.editable = true
	input_line_edit.grab_focus()
	input_line_edit.call_deferred("grab_focus")
	while not input_submitted:
		await get_tree().process_frame
	input_panel.hide()
	return input_result


func play_static_sound(duration_sec: float = 1.05) -> void:
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration_sec)
	var audio_data := PackedByteArray()
	audio_data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260415
	var filtered := 0.0
	for index in range(sample_count):
		var t := float(index) / sample_rate
		var fade_in := minf(1.0, t / 0.06)
		var fade_out := minf(1.0, (duration_sec - t) / 0.14)
		var pulse := 0.55 + 0.45 * sin(TAU * 7.5 * t)
		var white := rng.randf_range(-1.0, 1.0)
		filtered = filtered * 0.45 + white * 0.55
		var crackle := rng.randf_range(-0.9, 0.9) if rng.randf() < 0.04 else 0.0
		var hum_gate := 1.0 if sin(TAU * 4.0 * t) >= 0.35 else 0.0
		var hum := sin(TAU * 1120.0 * t) * 0.08 * hum_gate
		var sample := clampf((filtered * 0.34 + crackle * 0.25 + hum) * pulse * fade_in * fade_out, -1.0, 1.0)
		audio_data.encode_s16(index * 2, int(sample * 32767.0))
	_play_pcm_samples(sample_rate, audio_data)


func play_rocket_rumble(duration_sec: float = 4.6) -> void:
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration_sec)
	var audio_data := PackedByteArray()
	audio_data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	var low_noise := 0.0
	for index in range(sample_count):
		var t := float(index) / sample_rate
		var ramp_up := minf(1.0, t / 0.6)
		var fade_out := minf(1.0, (duration_sec - t) / 1.1)
		var white := rng.randf_range(-1.0, 1.0)
		low_noise = low_noise * 0.92 + white * 0.08
		var sub := sin(TAU * (38.0 + t * 4.0) * t) * 0.35 + sin(TAU * 64.0 * t) * 0.2
		var crackle := rng.randf_range(-0.5, 0.5) if rng.randf() < 0.08 else 0.0
		var sample := clampf((low_noise * 0.65 + sub * 0.4 + crackle * 0.14) * ramp_up * fade_out, -1.0, 1.0)
		audio_data.encode_s16(index * 2, int(sample * 32767.0))
	_play_pcm_samples(sample_rate, audio_data)


func play_ceremony_ambiance() -> void:
	var sample_rate := 22050
	var duration_sec := 5.0
	var sample_count := int(sample_rate * duration_sec)
	var audio_data := PackedByteArray()
	audio_data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260720
	var applause_filter := 0.0
	var chord_notes := [261.63, 329.63, 392.00, 523.25]
	for index in range(sample_count):
		var t := float(index) / sample_rate
		var fanfare := 0.0
		for note_i in range(chord_notes.size()):
			var note_start := float(note_i) * 0.26
			if t >= note_start:
				var dt := t - note_start
				var env := minf(1.0, dt / 0.08) * exp(-dt * 0.72)
				var freq: float = chord_notes[note_i]
				fanfare += (sin(TAU * freq * t) * 0.7 + sin(TAU * freq * 2.0 * t) * 0.18) * env * 0.22
		applause_filter = applause_filter * 0.72 + rng.randf_range(-1.0, 1.0) * 0.28
		var applause_env := minf(1.0, maxf(0.0, (t - 0.5) / 1.0)) * minf(1.0, (duration_sec - t) / 1.2)
		var clap_mod := 0.7 + 0.3 * sin(TAU * 9.0 * t + rng.randf_range(-0.3, 0.3))
		var applause := applause_filter * 0.11 * applause_env * clap_mod
		audio_data.encode_s16(index * 2, int(clampf(fanfare + applause, -1.0, 1.0) * 32767.0))
	_play_pcm_samples(sample_rate, audio_data)


func set_hud_visible(visible_state: bool) -> void:
	indicator_enabled = visible_state
	if is_instance_valid(mission_panel):
		mission_panel.visible = visible_state
	if is_instance_valid(arrow) and not visible_state:
		arrow.hide()


func fade_to_black(duration: float = 0.9) -> void:
	if not is_instance_valid(fade_overlay):
		return
	fade_overlay.show()
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, duration)
	await tween.finished


func fade_from_black(duration: float = 0.9, start_black: bool = true) -> void:
	if not is_instance_valid(fade_overlay):
		return
	if start_black:
		fade_overlay.modulate.a = 1.0
	fade_overlay.show()
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, duration)
	await tween.finished
	fade_overlay.hide()


func show_static_screen(duration: float = 2.0) -> void:
	if is_instance_valid(static_overlay):
		static_overlay.show()
	play_static_sound(duration)
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(static_overlay):
		static_overlay.hide()


func show_end_credits(ending_title: String, ending_subtitle: String, extra_detail: String = "") -> void:
	set_hud_visible(false)
	clear_radiation_warning()
	if is_instance_valid(dialogue_panel):
		dialogue_panel.hide()
	if is_instance_valid(static_overlay):
		static_overlay.hide()
	if is_instance_valid(fade_overlay):
		fade_overlay.hide()
	_populate_credits_panel(ending_title, ending_subtitle, extra_detail)
	if is_instance_valid(credits_panel):
		credits_panel.modulate.a = 0.0
		credits_panel.show()
		var fade_in := create_tween()
		fade_in.tween_property(credits_panel, "modulate:a", 1.0, 0.8)
		await fade_in.finished
		var scroll_node := credits_panel.get_node_or_null("ScrollMask/ScrollBody") as Control
		var mask_node := credits_panel.get_node_or_null("ScrollMask") as Control
		if scroll_node != null and mask_node != null:
			var target_y := maxf(0.0, (mask_node.size.y - scroll_node.size.y) / 2.0)
			scroll_node.position.y = mask_node.size.y
			var scroll_tween := create_tween()
			scroll_tween.tween_property(scroll_node, "position:y", target_y, 4.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			await scroll_tween.finished


func show_game_over(message: String) -> void:
	if game_over_visible:
		return
	game_over_visible = true
	clear_radiation_warning()
	dialogue_panel.hide()
	game_over_detail.text = message
	game_over_panel.show()
	indicator_enabled = false
	arrow.hide()
	if is_instance_valid(player):
		player.set_physics_process(false)


func hide_hud() -> void:
	indicator_enabled = false
	arrow.hide()
	visible = false


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
	dialogue_panel.custom_minimum_size = Vector2(760, 225)
	dialogue_panel.add_theme_stylebox_override("panel", _panel_style(Color("101a2bf2"), Color("71dcff")))
	dialogue_panel.gui_input.connect(_on_dialogue_panel_gui_input)
	add_child(dialogue_panel)

	var layout := VBoxContainer.new()
	dialogue_layout = layout
	layout.add_theme_constant_override("separation", 8)
	layout.mouse_filter = Control.MOUSE_FILTER_PASS
	dialogue_panel.add_child(layout)

	speaker_label = Label.new()
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.add_theme_color_override("font_color", Color("71dcff"))
	speaker_label.add_theme_font_size_override("font_size", 20)
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(speaker_label)

	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color("426179"))
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(separator)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(710, 76)
	message_label.add_theme_color_override("font_color", Color("f4f7ff"))
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(message_label)

	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	layout.add_child(actions)
	advance_button = Button.new()
	advance_button.text = "click to advance to next dialogue or wait"
	advance_button.flat = true
	advance_button.custom_minimum_size = Vector2(280, 24)
	advance_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	advance_button.add_theme_color_override("font_color", Color("aab8c9"))
	advance_button.add_theme_font_size_override("font_size", 12)
	advance_button.pressed.connect(_on_advance_button_pressed)
	layout.add_child(advance_button)
	advance_button.hide()
	dialogue_panel.hide()


func _build_interaction_hint() -> void:
	interaction_hint = Label.new()
	interaction_hint.text = ""
	interaction_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_hint.add_theme_color_override("font_color", Color("f4f7ff"))
	interaction_hint.add_theme_font_size_override("font_size", 16)
	interaction_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	interaction_hint.offset_top = -76
	interaction_hint.offset_bottom = -42
	interaction_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(interaction_hint)
	interaction_hint.hide()


func _build_warning_display() -> void:
	storm_overlay = _SandstormOverlay.new()
	storm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	storm_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storm_overlay.z_index = 5
	storm_overlay.hide()
	add_child(storm_overlay)

	warning_panel = PanelContainer.new()
	warning_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	warning_panel.offset_left = 280
	warning_panel.offset_top = 18
	warning_panel.offset_right = -280
	warning_panel.offset_bottom = 94
	warning_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("591616f0"), Color("ff4242"))
	)
	warning_panel.z_index = 6
	add_child(warning_panel)
	warning_label = Label.new()
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning_label.add_theme_color_override("font_color", Color("fff3f3"))
	warning_label.add_theme_font_size_override("font_size", 23)
	warning_panel.add_child(warning_label)
	warning_panel.hide()


func _build_notification() -> void:
	notification_label = Label.new()
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	notification_label.offset_top = 112
	notification_label.offset_bottom = 150
	notification_label.add_theme_color_override("font_color", Color("9bffae"))
	notification_label.add_theme_font_size_override("font_size", 24)
	notification_label.z_index = 8
	add_child(notification_label)
	notification_label.hide()


func _build_information_panel() -> void:
	information_panel = PanelContainer.new()
	information_panel.set_anchors_preset(Control.PRESET_CENTER)
	information_panel.position = Vector2(-280, -170)
	information_panel.size = Vector2(560, 340)
	information_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("101a2bf5"), Color("71dcff"))
	)
	information_panel.z_index = 12
	add_child(information_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	information_panel.add_child(layout)
	information_title = Label.new()
	information_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	information_title.add_theme_color_override("font_color", Color("71dcff"))
	information_title.add_theme_font_size_override("font_size", 22)
	layout.add_child(information_title)
	information_text = Label.new()
	information_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	information_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	information_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	information_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	information_text.add_theme_color_override("font_color", Color("f4f7ff"))
	information_text.add_theme_font_size_override("font_size", 18)
	layout.add_child(information_text)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(150, 42)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(_on_information_close_requested)
	layout.add_child(close_button)
	information_panel.hide()


func _build_input_panel() -> void:
	input_panel = PanelContainer.new()
	input_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	input_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	input_panel.custom_minimum_size = Vector2(520.0, 270.0)
	input_panel.size = Vector2(520.0, 270.0)
	input_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("101a2bf5"), Color("71dcff"))
	)
	input_panel.z_index = 14
	add_child(input_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	input_panel.add_child(layout)

	input_title = Label.new()
	input_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_title.add_theme_color_override("font_color", Color("71dcff"))
	input_title.add_theme_font_size_override("font_size", 22)
	layout.add_child(input_title)

	input_prompt = Label.new()
	input_prompt.custom_minimum_size = Vector2(460.0, 48.0)
	input_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input_prompt.add_theme_color_override("font_color", Color("f4f7ff"))
	input_prompt.add_theme_font_size_override("font_size", 18)
	layout.add_child(input_prompt)

	var line_normal := _panel_style(Color("070f1df8"), Color("48a9d6"))
	line_normal.content_margin_left = 12.0
	line_normal.content_margin_top = 8.0
	line_normal.content_margin_right = 12.0
	line_normal.content_margin_bottom = 8.0
	var line_focus := _panel_style(Color("070f1df8"), Color("71dcff"))
	line_focus.content_margin_left = 12.0
	line_focus.content_margin_top = 8.0
	line_focus.content_margin_right = 12.0
	line_focus.content_margin_bottom = 8.0

	input_line_edit = LineEdit.new()
	input_line_edit.custom_minimum_size = Vector2(380, 44)
	input_line_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	input_line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_line_edit.max_length = 28
	input_line_edit.editable = true
	input_line_edit.caret_blink = true
	input_line_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	input_line_edit.add_theme_stylebox_override("normal", line_normal)
	input_line_edit.add_theme_stylebox_override("focus", line_focus)
	input_line_edit.add_theme_font_size_override("font_size", 18)
	input_line_edit.text_submitted.connect(_on_input_text_submitted)
	layout.add_child(input_line_edit)

	input_error_label = Label.new()
	input_error_label.text = "Please enter a name for your discovery."
	input_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_error_label.add_theme_color_override("font_color", Color("ff7676"))
	input_error_label.add_theme_font_size_override("font_size", 14)
	input_error_label.hide()
	layout.add_child(input_error_label)

	var confirm_button := Button.new()
	confirm_button.text = "Confirm"
	confirm_button.custom_minimum_size = Vector2(160, 42)
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm_button.add_theme_font_size_override("font_size", 17)
	confirm_button.pressed.connect(_on_input_confirm_pressed)
	layout.add_child(confirm_button)
	input_panel.hide()


func _on_input_text_submitted(_new_text: String) -> void:
	_on_input_confirm_pressed()


func _on_input_confirm_pressed() -> void:
	var trimmed := input_line_edit.text.strip_edges()
	if trimmed.is_empty():
		input_error_label.show()
		input_line_edit.grab_focus()
		return
	input_result = trimmed
	input_submitted = true


func _build_game_over_panel() -> void:
	game_over_panel = PanelContainer.new()
	game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_over_panel.position = Vector2(-250, -145)
	game_over_panel.size = Vector2(500, 290)
	game_over_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("17131bf5"), Color("ff5f5f"))
	)
	game_over_panel.z_index = 20
	add_child(game_over_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	game_over_panel.add_child(layout)
	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("ff7676"))
	title.add_theme_font_size_override("font_size", 30)
	layout.add_child(title)
	game_over_detail = Label.new()
	game_over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_over_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_over_detail.add_theme_color_override("font_color", Color("f4f7ff"))
	game_over_detail.add_theme_font_size_override("font_size", 17)
	layout.add_child(game_over_detail)
	var game_over_actions := HBoxContainer.new()
	game_over_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	game_over_actions.add_theme_constant_override("separation", 18)
	layout.add_child(game_over_actions)
	var try_again := Button.new()
	try_again.text = "Try Again"
	try_again.custom_minimum_size = Vector2(150, 42)
	try_again.pressed.connect(_on_try_again_pressed)
	game_over_actions.add_child(try_again)
	var exit_button := Button.new()
	exit_button.text = "Exit"
	exit_button.custom_minimum_size = Vector2(150, 42)
	exit_button.pressed.connect(_on_exit_pressed)
	game_over_actions.add_child(exit_button)
	game_over_panel.hide()


func _layout_dialogue_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if is_instance_valid(dialogue_panel):
		var dialogue_height := 248.0 if not buttons.is_empty() else 225.0
		dialogue_panel.custom_minimum_size = Vector2(760.0, dialogue_height)
		dialogue_panel.size = Vector2(minf(760.0, viewport_size.x - 32.0), dialogue_height)
		dialogue_panel.position = Vector2(
			(viewport_size.x - dialogue_panel.size.x) / 2.0,
			viewport_size.y - dialogue_panel.size.y - 22.0
		)
	if is_instance_valid(input_panel):
		var width := minf(520.0, viewport_size.x - 32.0)
		if is_instance_valid(input_prompt):
			input_prompt.custom_minimum_size = Vector2(maxf(240.0, width - 60.0), 48.0)
		input_panel.custom_minimum_size = Vector2(width, 270.0)
		input_panel.reset_size()
		input_panel.size = Vector2(maxf(width, input_panel.size.x), maxf(270.0, input_panel.size.y))
		input_panel.position = (viewport_size - input_panel.size) / 2.0


func _unhandled_input(event: InputEvent) -> void:
	if not dialogue_waiting:
		return
	if event.is_action_pressed("ui_accept") or (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_finish_dialogue(dialogue_generation)
		get_viewport().set_input_as_handled()


func _on_dialogue_panel_gui_input(event: InputEvent) -> void:
	if (
		dialogue_waiting
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_finish_dialogue(dialogue_generation)
		dialogue_panel.accept_event()


func _finish_dialogue(generation: int) -> void:
	if generation == dialogue_generation:
		dialogue_waiting = false


func _on_advance_button_pressed() -> void:
	_finish_dialogue(dialogue_generation)


func is_busy() -> bool:
	return (
		dialogue_waiting
		or game_over_visible
		or (dialogue_panel != null and dialogue_panel.visible)
		or (information_panel != null and information_panel.visible)
		or (input_panel != null and input_panel.visible)
		or (credits_panel != null and credits_panel.visible)
	)


func _process(delta: float) -> void:
	_update_indicator(delta)
	if warning_panel.visible:
		_update_warning_countdown()


func _update_warning_countdown() -> void:
	var instruction := "REACH THE RADIATION ROOM NOW" if radiation_shelter_urgency else "REACH THE SAFETY BUILDING"
	warning_label.text = "RADIATION LEVEL: HIGH\n%s — %d s" % [
		instruction, Global.radiation_seconds_remaining()
	]


func _play_warning_beep() -> void:
	var sample_rate := 22050
	var sample_count := int(sample_rate * 0.28)
	var audio_data := PackedByteArray()
	audio_data.resize(sample_count * 2)
	for index in range(sample_count):
		var envelope := 1.0 - float(index) / sample_count
		var sample := sin(TAU * 880.0 * float(index) / sample_rate) * envelope * 0.5
		audio_data.encode_s16(index * 2, int(sample * 32767.0))
	_play_pcm_samples(sample_rate, audio_data)


func _play_pcm_samples(sample_rate: int, audio_data: PackedByteArray) -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = audio_data
	var player_node := AudioStreamPlayer.new()
	player_node.stream = stream
	add_child(player_node)
	player_node.finished.connect(player_node.queue_free)
	player_node.play()


func _on_try_again_pressed() -> void:
	Global.retry_from_last_completed_mission()


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_information_close_requested() -> void:
	information_panel.hide()


func _update_indicator(delta: float) -> void:
	if not indicator_enabled:
		arrow.hide()
		return
	if not is_instance_valid(player) or not is_instance_valid(mission_target):
		mission_status.text = "OBJECTIVE"
		arrow.hide()
		return
	var target_position := _get_target_position()
	var world_direction := target_position - player.global_position
	var target_area := mission_target as Area2D
	var target_reached := target_area.overlaps_body(player) if target_area != null else world_direction.length() < 24.0
	mission_status.text = "AREA REACHED" if target_reached else "IN PROGRESS"
	if world_direction.length_squared() < 1.0:
		arrow.hide()
		return
	var target_angle := world_direction.angle()
	if indicator_initialized:
		var rotation_weight := 1.0 - exp(-12.0 * delta)
		arrow.global_rotation = lerp_angle(arrow.global_rotation, target_angle, rotation_weight)
	else:
		arrow.global_rotation = target_angle
		indicator_initialized = true
	var direction := Vector2.RIGHT.rotated(arrow.global_rotation)
	var desired_position := player.global_position + direction * 42.0
	if delta > 0.0:
		var position_weight := 1.0 - exp(-18.0 * delta)
		arrow.global_position = arrow.global_position.lerp(desired_position, position_weight)
	else:
		arrow.global_position = desired_position
	arrow.visible = not target_reached


func _get_target_position() -> Vector2:
	if mission_target is Area2D:
		var collision_shape := mission_target.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision_shape != null:
			return collision_shape.global_position
	return mission_target.global_position


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


func _build_screen_overlays() -> void:
	static_overlay = _StaticNoiseOverlay.new()
	static_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	static_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	static_overlay.z_index = 25
	static_overlay.hide()
	add_child(static_overlay)

	fade_overlay = ColorRect.new()
	fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	fade_overlay.modulate.a = 0.0
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	fade_overlay.z_index = 28
	fade_overlay.hide()
	add_child(fade_overlay)

	credits_panel = Control.new()
	credits_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	credits_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	credits_panel.z_index = 32
	credits_panel.hide()
	add_child(credits_panel)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("070c17fa")
	credits_panel.add_child(backdrop)

	var scroll_mask := Control.new()
	scroll_mask.name = "ScrollMask"
	scroll_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_mask.offset_left = 80
	scroll_mask.offset_top = 42
	scroll_mask.offset_right = -80
	scroll_mask.offset_bottom = -96
	scroll_mask.clip_contents = true
	credits_panel.add_child(scroll_mask)

	var scroll_body := VBoxContainer.new()
	scroll_body.name = "ScrollBody"
	scroll_body.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scroll_body.add_theme_constant_override("separation", 12)
	scroll_mask.add_child(scroll_body)

	var bottom_bar := HBoxContainer.new()
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -76
	bottom_bar.offset_bottom = -24
	bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_bar.add_theme_constant_override("separation", 20)
	credits_panel.add_child(bottom_bar)

	var play_again := Button.new()
	play_again.text = "Play Again"
	play_again.custom_minimum_size = Vector2(160, 42)
	play_again.pressed.connect(_on_play_again_pressed)
	bottom_bar.add_child(play_again)

	var main_menu := Button.new()
	main_menu.text = "Main Menu"
	main_menu.custom_minimum_size = Vector2(160, 42)
	main_menu.pressed.connect(_on_main_menu_pressed)
	bottom_bar.add_child(main_menu)

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.custom_minimum_size = Vector2(140, 42)
	exit_btn.pressed.connect(_on_exit_pressed)
	bottom_bar.add_child(exit_btn)


func _populate_credits_panel(ending_title: String, ending_subtitle: String, extra_detail: String) -> void:
	if not is_instance_valid(credits_panel):
		return
	var scroll_body := credits_panel.get_node_or_null("ScrollMask/ScrollBody") as VBoxContainer
	if scroll_body == null:
		return
	for child in scroll_body.get_children():
		child.queue_free()

	var commander := Global.get_player_display_name()
	var suit := Global.player_gender if not Global.player_gender.is_empty() else "Astronaut"
	var sample := Global.discovery_name if not Global.discovery_name.is_empty() else "Unclassified Mars Sample"

	var entries := [
		["SPATIAL TASK FORCE (SpTF)", 30, Color("71dcff")],
		[ending_title, 22, Color("f5cb69")],
		[ending_subtitle, 17, Color("f4f7ff")],
		["", 10, Color.WHITE],
		["Commander: %s (%s)" % [commander, suit], 18, Color("d8ecff")],
		["Discovery Logged: %s" % sample, 18, Color("9bffae")],
		[extra_detail, 16, Color("aab8c9")],
		["", 10, Color.WHITE],
		["SPACE WEATHER DATA", 16, Color("71dcff")],
		["NASA CCMC DONKI API — Solar Flare & Radiation Telemetry", 15, Color("f4f7ff")],
		["", 8, Color.WHITE],
		["END CREDITS", 20, Color("f5cb69")],
		["Team SpTF — NASA Space Apps Challenge 2026", 17, Color("f4f7ff")],
		["Thank you for playing!", 20, Color("71dcff")]
	]
	for entry in entries:
		var line_text: String = entry[0]
		if line_text.is_empty():
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, int(entry[1]))
			scroll_body.add_child(spacer)
			continue
		var label := Label.new()
		label.text = line_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", int(entry[1]))
		label.add_theme_color_override("font_color", entry[2])
		scroll_body.add_child(label)


func _on_play_again_pressed() -> void:
	Global.reset_mission()
	get_tree().change_scene_to_file("res://Scenes/choose_gender.tscn")


func _on_main_menu_pressed() -> void:
	Global.reset_mission()
	get_tree().change_scene_to_file("res://main_menu.tscn")


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


class _SandstormOverlay:
	extends Control

	var elapsed := 0.0

	func _process(delta: float) -> void:
		elapsed += delta
		queue_redraw()

	func _draw() -> void:
		var viewport_size := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.65, 0.31, 0.09, 0.13))
		for index in range(55):
			var start_x := fposmod(float(index) * 131.0 - elapsed * 210.0, viewport_size.x + 100.0)
			var y := fposmod(float(index) * 79.0 + elapsed * 42.0, viewport_size.y)
			draw_line(
				Vector2(start_x, y),
				Vector2(start_x + 38.0, y - 5.0),
				Color(1.0, 0.69, 0.37, 0.28),
				2.0
			)


class _StaticNoiseOverlay:
	extends Control

	var elapsed := 0.0
	var rng := RandomNumberGenerator.new()

	func _init() -> void:
		rng.seed = 4242

	func _process(delta: float) -> void:
		if visible:
			elapsed += delta
			queue_redraw()

	func _draw() -> void:
		var viewport_size := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.03, 0.04, 0.06, 0.94))
		rng.seed = int(elapsed * 60.0) + 17
		for _i in range(180):
			var y := rng.randf_range(0.0, viewport_size.y)
			var x := rng.randf_range(0.0, viewport_size.x)
			var w := rng.randf_range(18.0, 140.0)
			var brightness := rng.randf_range(0.35, 0.92)
			var alpha := rng.randf_range(0.12, 0.45)
			draw_line(
				Vector2(x, y),
				Vector2(x + w, y),
				Color(brightness, brightness, brightness, alpha),
				rng.randf_range(1.0, 3.0)
			)
		var font := ThemeDB.fallback_font
		if font != null:
			var label_text := "*static*"
			var font_size := 34
			var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var pos := (viewport_size - text_size) / 2.0 + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			draw_string(font, pos + Vector2(0, text_size.y * 0.75), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("d8e2ef"))
