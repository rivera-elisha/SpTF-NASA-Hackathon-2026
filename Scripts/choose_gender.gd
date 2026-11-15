
extends Control

@onready var male_button: TextureButton = $HBoxContainer/MaleButton
@onready var female_button: TextureButton = $HBoxContainer/FemaleButton
@onready var middle_character: AnimatedSprite2D = $MiddleCharacter
@onready var back_button: TextureButton = $backButton

# Name popup nodes
@onready var name_panel: Control = $NamePanel
@onready var name_line_edit: LineEdit = $NamePanel/NameLineEdit
@onready var enter_name_button: Button = $NamePanel/EnterNameButton

# Next scene
const MAIN_MENU_SCENE = "res://main_menu.tscn"
const NEXT_SCENE = "res://Scenes/Room_1.tscn"

var is_animating = false


func _ready():
	# Show and continuously rotate the center character
	middle_character.visible = true
	middle_character.play()

	# Hide name popup when the scene starts
	name_panel.hide()

	# Connect gender buttons
	male_button.pressed.connect(_on_male_pressed)
	female_button.pressed.connect(_on_female_pressed)

	# Connect name button
	enter_name_button.pressed.connect(_on_enter_name_pressed)

	# Connect back button to return to main menu
	if back_button:
		back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed():
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_male_pressed():
	select_gender(male_button, "Male")


func _on_female_pressed():
	select_gender(female_button, "Female")


func select_gender(selected_button: TextureButton, gender: String):

	if is_animating:
		return

	is_animating = true

	# Save selected gender
	Global.player_gender = gender

	# Disable both buttons
	male_button.disabled = true
	female_button.disabled = true

	# Calculate center position
	var target_position = middle_character.global_position - (selected_button.size / 2.0)

	# Reserve the selected button's original space
	var placeholder = Control.new()
	placeholder.custom_minimum_size = selected_button.size
	placeholder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Insert placeholder where the selected button was
	var button_index = selected_button.get_index()
	$HBoxContainer.add_child(placeholder)
	$HBoxContainer.move_child(placeholder, button_index)

	# Move selected button out of HBoxContainer
	selected_button.reparent(self, true)

	# Move selected button toward the center
	var tween = create_tween()

	tween.tween_property(
		selected_button,
		"global_position",
		target_position,
		1.0
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Wait until the button reaches the center
	await tween.finished

	# Stop the center character's animation
	middle_character.stop()

	# Keep your original character behavior
	middle_character.visible = true
	selected_button.visible = false

	is_animating = false

	# Show name popup
	name_panel.show()
	name_line_edit.grab_focus()


# Handle player name input
func _on_enter_name_pressed():

	var player_name = name_line_edit.text.strip_edges()

	# Check if name is empty
	if player_name.is_empty():
		print("Please enter your character name!")
		name_line_edit.grab_focus()
		return

	# Save player information
	Global.player_name = player_name
	Global.reset_mission()

	print("Player Name: ", Global.player_name)
	print("Player Gender: ", Global.player_gender)

	# Change to next scene
	print("Loading Room_1...")

	var error = get_tree().change_scene_to_file(NEXT_SCENE)

	if error != OK:
		print("ERROR: Could not load scene!")
		print("Check your scene path: ", NEXT_SCENE)
