
extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var map_sprite: Sprite2D = $Background
@onready var camera: Camera2D = $WorldObjects/CharacterBody2d/Camera2D
@onready var player: CharacterBody2D = $WorldObjects/CharacterBody2d

func _ready():
	# Check node references
	if map_sprite == null:
		push_error("Background Sprite2D not found!")
		return

	if camera == null:
		push_error("Player Camera2D not found!")
		return

	# Calculate the map's actual world boundaries
	var map_bounds: Rect2 = (
		map_sprite.get_global_transform() * map_sprite.get_rect()
	)

	# Apply boundaries to the camera
	camera.limit_left = floori(map_bounds.position.x)
	camera.limit_top = floori(map_bounds.position.y)
	camera.limit_right = ceili(map_bounds.end.x)
	camera.limit_bottom = ceili(map_bounds.end.y)

	var dialogue: CanvasLayer = DialogueController.new()
	add_child(dialogue)
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
	elif not Global.map_intro_shown:
		Global.map_intro_shown = true
		dialogue.set_mission("Explore the Personal Building and find the Exercise Room.", $WorldObjects/PersonalBuilding/ExerciseDoor)
		player.set_physics_process(false)
		await dialogue.say("Outpost Guide", "This is your whole Mars Outpost. Proceed to the other rooms and find the exercise room.")
		await dialogue.say("Outpost Guide", "The Exercise Room is in the Personal Building.")
		player.set_physics_process(true)
	elif Global.static_message_pending:
		dialogue.set_mission("Find the Communications room.", $WorldObjects/SafetyBuilding/PersonalDoor)
		player.set_physics_process(false)
		await dialogue.say(
			"Communications",
			"(Static sound) It seems someone is messaging you in the Communications room. Go to the other room outside."
		)
		player.set_physics_process(true)
	else:
		dialogue.set_mission("Explore the outpost.", $WorldObjects/MainBuilding/MainDoor)
