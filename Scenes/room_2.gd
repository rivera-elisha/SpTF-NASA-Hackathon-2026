extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var player: CharacterBody2D = $CharacterBody2d

var dialogue: CanvasLayer
var exercise_prompt_started := false


func _ready() -> void:
	dialogue = DialogueController.new()
	add_child(dialogue)
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
		return
	if Global.exercise_prompt_completed:
		dialogue.set_mission("Return outside to the outpost.", $ExitMainDoor)
		return
	dialogue.set_mission("Find the Exercise Room.", $ExerciseArea)
	$ExerciseArea.body_entered.connect(_on_exercise_area_body_entered)


func _on_exercise_area_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D or exercise_prompt_started:
		return
	exercise_prompt_started = true
	player.set_physics_process(false)
	await dialogue.say(
		"Exercise Room",
		"This is the Exercise Room where we will train your bones and muscles just like on Earth."
	)
	var exercised: bool = await dialogue.choose("Exercise", "Start Exercise?", "Yes", "No")
	Global.exercise_prompt_completed = true
	if exercised:
		await dialogue.say("Exercise", "Exercise in progress...", 0.0)
		await get_tree().create_timer(3.0).timeout
		await dialogue.say("Exercise", "Exercise complete. Great work, Commander!")
		Global.movement_speed_multiplier = 1.0
	else:
		Global.movement_speed_multiplier = 0.5
		await dialogue.say("Exercise", "You skipped exercise. Your movement will deteriorate on Mars.")
	dialogue.set_mission("Return outside to the outpost.", $ExitMainDoor)
	player.set_physics_process(true)
	Global.static_message_pending = true
