extends Control

const InteractiveAssets = preload("res://Scripts/interactive_assets.gd")

@onready var male_card: PanelContainer = $StageRow/MaleCard
@onready var female_card: PanelContainer = $StageRow/FemaleCard
@onready var male_button: TextureButton = $StageRow/MaleCard/MaleVBox/PortraitFrame/MaleButton
@onready var female_button: TextureButton = $StageRow/FemaleCard/FemaleVBox/PortraitFrame/FemaleButton
@onready var holopad_glow: Panel = $StageRow/SuitPreviewCard/PreviewVBox/PreviewStage/HolopadGlow
@onready var middle_character: AnimatedSprite2D = $StageRow/SuitPreviewCard/PreviewVBox/PreviewStage/MiddleCharacter
@onready var back_button: TextureButton = $backButton
@onready var name_modal: ColorRect = $NameModal
@onready var name_panel: PanelContainer = $NameModal/NamePanel
@onready var selected_profile_label: Label = $NameModal/NamePanel/NameVBox/SelectedProfileLabel
@onready var name_line_edit: LineEdit = $NameModal/NamePanel/NameVBox/NameLineEdit
@onready var error_label: Label = $NameModal/NamePanel/NameVBox/ErrorLabel
@onready var cancel_button: Button = $NameModal/NamePanel/NameVBox/ButtonRow/CancelButton
@onready var enter_name_button: Button = $NameModal/NamePanel/NameVBox/ButtonRow/EnterNameButton

var _selected_gender := ""
var _holo_time := 0.0
var _male_base_style: StyleBoxFlat
var _female_base_style: StyleBoxFlat


func _ready() -> void:
	name_modal.visible = false
	error_label.text = ""
	# Guarantee the name field stays fixed-width even with long names.
	name_line_edit.expand_to_text_length = false
	name_line_edit.clip_contents = true
	name_line_edit.custom_minimum_size = Vector2(380, 46)

	middle_character.play("default")

	_male_base_style = male_card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_female_base_style = female_card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	male_card.add_theme_stylebox_override("panel", _male_base_style)
	female_card.add_theme_stylebox_override("panel", _female_base_style)

	_bind_card(male_card, _male_base_style, male_button, "Male", Color(0.42, 0.85, 1.0, 1.0))
	_bind_card(female_card, _female_base_style, female_button, "Female", Color(1.0, 0.62, 0.82, 1.0))

	back_button.pressed.connect(_on_back_pressed)
	cancel_button.pressed.connect(_close_name_modal)
	enter_name_button.pressed.connect(_on_enter_name_pressed)
	name_line_edit.text_submitted.connect(_on_name_text_submitted)
	name_line_edit.text_changed.connect(_on_name_text_changed)

	back_button.mouse_entered.connect(_on_back_hover.bind(true))
	back_button.mouse_exited.connect(_on_back_hover.bind(false))

	await get_tree().process_frame
	if is_instance_valid(male_card):
		male_card.pivot_offset = male_card.size * 0.5
	if is_instance_valid(female_card):
		female_card.pivot_offset = female_card.size * 0.5
	if is_instance_valid(back_button):
		back_button.pivot_offset = back_button.size * 0.5
	if is_instance_valid(name_panel):
		name_panel.pivot_offset = name_panel.size * 0.5


func _process(delta: float) -> void:
	_holo_time += delta
	if is_instance_valid(holopad_glow):
		var pulse := 0.72 + 0.24 * sin(_holo_time * 3.0)
		holopad_glow.modulate = Color(pulse, 0.92 + 0.08 * sin(_holo_time * 2.0), 1.0, 1.0)
	if is_instance_valid(middle_character):
		middle_character.position.y = 114.0 + sin(_holo_time * 2.4) * 3.0


func _unhandled_input(event: InputEvent) -> void:
	if name_modal.visible and event.is_action_pressed("ui_cancel"):
		_close_name_modal()
		get_viewport().set_input_as_handled()


func _bind_card(
	card: PanelContainer,
	style: StyleBoxFlat,
	button: TextureButton,
	gender: String,
	accent_color: Color
) -> void:
	button.pressed.connect(_on_gender_selected.bind(gender))
	card.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_gender_selected(gender)
	)
	var default_border := style.border_color
	var default_bg := style.bg_color
	var on_enter := func() -> void:
		card.pivot_offset = card.size * 0.5
		style.border_color = accent_color
		style.bg_color = Color(0.075, 0.13, 0.235, 0.96)
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2(1.03, 1.03), 0.12).set_trans(Tween.TRANS_QUAD)
	var on_exit := func() -> void:
		if _selected_gender != gender or not name_modal.visible:
			style.border_color = default_border
			style.bg_color = default_bg
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD)

	card.mouse_entered.connect(on_enter)
	card.mouse_exited.connect(on_exit)
	button.mouse_entered.connect(on_enter)
	button.mouse_exited.connect(on_exit)


func _on_back_hover(hovered: bool) -> void:
	back_button.pivot_offset = back_button.size * 0.5
	var target := Vector2(1.08, 1.08) if hovered else Vector2.ONE
	create_tween().tween_property(back_button, "scale", target, 0.1)


func _on_gender_selected(gender: String) -> void:
	_selected_gender = gender
	InteractiveAssets.play_sfx(self, "interact")
	_open_name_popup()


func _open_name_popup() -> void:
	var badge_color := Color(0.45, 0.85, 1.0, 1.0) if _selected_gender == "Male" else Color(1.0, 0.7, 0.86, 1.0)
	selected_profile_label.text = "PROFILE: %s COMMANDER" % _selected_gender.to_upper()
	selected_profile_label.add_theme_color_override("font_color", badge_color)
	error_label.text = ""

	name_modal.visible = true
	name_modal.modulate.a = 0.0
	name_panel.pivot_offset = name_panel.size * 0.5
	name_panel.scale = Vector2(0.92, 0.92)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(name_modal, "modulate:a", 1.0, 0.14)
	tw.tween_property(name_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	name_line_edit.grab_focus()
	name_line_edit.caret_column = name_line_edit.text.length()


func _close_name_modal() -> void:
	if not name_modal.visible:
		return
	InteractiveAssets.play_sfx(self, "interact", -12.0)
	name_modal.visible = false
	error_label.text = ""
	_male_base_style.border_color = Color(0.219608, 0.439216, 0.690196, 0.9)
	_male_base_style.bg_color = Color(0.0509804, 0.0862745, 0.160784, 0.92)
	_female_base_style.border_color = Color(0.219608, 0.439216, 0.690196, 0.9)
	_female_base_style.bg_color = Color(0.0509804, 0.0862745, 0.160784, 0.92)


func _on_name_text_changed(_new_text: String) -> void:
	if error_label.text != "":
		error_label.text = ""


func _on_name_text_submitted(_submitted_text: String) -> void:
	_on_enter_name_pressed()


func _on_enter_name_pressed() -> void:
	var typed := name_line_edit.text.strip_edges()
	if typed.is_empty():
		error_label.text = "Please enter a commander name."
		InteractiveAssets.play_sfx(self, "interact", -10.0)
		name_line_edit.grab_focus()
		return
	if _selected_gender.is_empty():
		error_label.text = "Please select a commander profile first."
		return

	Global.player_gender = _selected_gender
	Global.player_name = typed
	Global.reset_mission()
	InteractiveAssets.play_sfx(self, "success")
	get_tree().change_scene_to_file("res://Scenes/Room_1.tscn")


func _on_back_pressed() -> void:
	InteractiveAssets.play_sfx(self, "interact", -10.0)
	get_tree().change_scene_to_file("res://main_menu.tscn")
