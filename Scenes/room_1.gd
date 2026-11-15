extends Node2D

@onready var dialogue_panel = $CanvasLayer/DialoguePanel
@onready var character_name = $CanvasLayer/DialoguePanel/VBoxContainer/CharacterName
@onready var dialogue_text = $CanvasLayer/DialoguePanel/VBoxContainer/DialogueText

# Change these paths to match your actual scene tree.
@onready var game_over_panel = $CanvasLayer/GameOverPanel
@onready var life_support_area = $LifeSupportArea
@onready var spacesuits_area = $SpacesuitsArea
@onready var exit_area = $ExitArea

var visited_life_support = false
var visited_spacesuits = false
var can_exit = false

var dialogue_running = false


func _ready():
	dialogue_panel.hide()
	game_over_panel.hide()

	show_popup_sequence()

# =====================================
# DIALOGUE SYSTEM
# =====================================

func show_dialogue(speaker: String, message: String, duration: float = 3.0):
	character_name.text = speaker
	dialogue_text.text = message

	dialogue_panel.show()

	await get_tree().create_timer(duration).timeout

	dialogue_panel.hide()


func show_popup_sequence():

	await show_dialogue(
		"Welcome to the Martian Outpost!",
		"Welcome to The Martian Outpost. Let's explore it!"
	)

	await get_tree().create_timer(0.1).timeout

	await show_dialogue(
		"Explore the main rooms.",
		"Let's get to know the main rooms within your outpost."
	)

	await get_tree().create_timer(0.1).timeout

	await show_dialogue(
		"Assigning mission...",
		"You can interact with objects around the room!"
	)

	await get_tree().create_timer(0.5).timeout

	await show_dialogue(
		"Go to the life support room.",
		"Go to the Life-support room and check its levels."
	)

func _on_life_support_area_body_entered(body):
	if body is CharacterBody2D:
		print("Entered Life Support!")
		enter_life_support()


func _on_spacesuits_area_body_entered(body):
	if body is CharacterBody2D:
		print("Entered Spacesuits!")
		enter_spacesuits()


func _on_exit_area_body_entered(body):
	if body is CharacterBody2D:
		print("Entered Exit!")
		enter_exit()
# =====================================
# LIFE-SUPPORT ROOM
# =====================================

func enter_life_support():

	if visited_life_support:
		return

	visited_life_support = true

	var oxygen = randi_range(85, 100)
	var co2 = randi_range(300, 1000)
	var temperature = randi_range(18, 25)

	var radiation = ["LOW", "HIGH"].pick_random()

	await show_dialogue(
		"Life-support System",
		"This is the Life-support room. Check this occasionally, especially the radiation levels!"
	)

	await show_dialogue(
		"System Readings",
		"Oxygen Level: %d%%\nCarbon Dioxide Level: %d ppm\nTemperature: %d°C\nRadiation Level: %s" % [
			oxygen,
			co2,
			temperature,
			radiation
		],
		5.0
	)

	await show_dialogue(
		"Mission",
		"Go to the Spacesuits room and proceed to the Exit."
	)


# =====================================
# SPACESUITS ROOM
# =====================================

func enter_spacesuits():

	if visited_spacesuits:
		return

	visited_spacesuits = true

	await show_dialogue(
		"Spacesuits System",
		"This is the Spacesuits room. Make sure your equipment is ready before going outside!"
	)

	await show_dialogue(
		"Mission",
		"You're now ready to explore the whole outpost."
	)

	check_exit_requirement()


# =====================================
# EXIT REQUIREMENTS
# =====================================

func check_exit_requirement():

	if visited_life_support and visited_spacesuits:
		can_exit = true

func enter_exit():

	if can_exit:
		get_tree().change_scene_to_file(
			"res://Scenes/mars_map.tscn"
		)
	else:
		game_over()


# =====================================
# GAME OVER
# =====================================

func game_over():

	dialogue_panel.hide()
	game_over_panel.show()


func _on_try_again_pressed():

	get_tree().reload_current_scene()


func _on_exit_pressed():

	get_tree().quit()
