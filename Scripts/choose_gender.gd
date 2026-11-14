
extends Control

@onready var male_button: TextureButton = $HBoxContainer/MaleButton
@onready var female_button: TextureButton = $HBoxContainer/FemaleButton
@onready var middle_character: AnimatedSprite2D = $MiddleCharacter

var is_animating = false

func _ready():
	# Show and continuously rotate the center character
	middle_character.visible = true
	middle_character.play()

	# Connect buttons
	male_button.pressed.connect(_on_male_pressed)
	female_button.pressed.connect(_on_female_pressed)


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

	# WAIT until the button reaches the center
	await tween.finished

	# NOW stop the center character's rotation
	middle_character.stop()

	# Hide the rotating center character
	middle_character.visible = true

	# Keep the selected character at the center
	selected_button.visible = false

	is_animating = false
