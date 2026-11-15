extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var player: CharacterBody2D = $CharacterBody2d

var dialogue: CanvasLayer
var exercise_prompt_started := false


func _ready() -> void:
	dialogue = DialogueController.new()
	add_child(dialogue)
	Global.radiation_warning_started.connect(_on_radiation_warning_started)
	Global.radiation_event_expired.connect(_on_radiation_event_expired)
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
		return
	if Global.exercise_prompt_completed:
		if Global.part4_rocket_boarding_ready and not Global.part4_ending_reached:
			dialogue.set_mission("Return outside and board the rocket ship.", $ExitMainDoor)
		elif Global.comms_static_part3_pending and not Global.comms_part3_arrived:
			dialogue.set_mission("Return outside and go to the Communication Room.", $ExitMainDoor)
		elif Global.all_solar_panels_cleaned() and not Global.discovery_named:
			dialogue.set_mission("Return outside and check the Main Laboratory Room.", $ExitMainDoor)
		elif Global.lab_analysis_started and not Global.all_solar_panels_cleaned():
			dialogue.set_mission("Return outside and clean the solar panels.", $ExitMainDoor)
		elif Global.glowing_object_collected and not Global.lab_analysis_started:
			dialogue.set_mission("Return outside and proceed to the Main Laboratory.", $ExitMainDoor)
		else:
			dialogue.set_mission("Return outside to the outpost.", $ExitMainDoor)
		return
	dialogue.set_mission("Find the Exercise Room.", $ExerciseArea)
	$ExerciseArea.body_entered.connect(_on_exercise_area_body_entered)
	if Global.radiation_warning_active:
		dialogue.show_radiation_warning()


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
	Global.did_exercise = exercised
	if exercised:
		await dialogue.say("Exercise", "Exercise in progress...", 0.0)
		await get_tree().create_timer(3.0).timeout
		dialogue.hide_dialogue()
		await dialogue.say("Exercise", "Exercise complete. Great work, Commander!")
		Global.movement_speed_multiplier = 1.0
	else:
		Global.movement_speed_multiplier = 0.5
		await dialogue.say("Exercise", "You skipped exercise. Your movement will deteriorate on Mars.")
	dialogue.set_mission("Return outside to the outpost.", $ExitMainDoor)
	player.set_physics_process(true)
	Global.static_message_pending = true


func _on_radiation_warning_started() -> void:
	dialogue.show_radiation_warning()


func _on_radiation_event_expired() -> void:
	dialogue.show_game_over("How I wish I was able to find it... The radiation storm caught me outside.")
