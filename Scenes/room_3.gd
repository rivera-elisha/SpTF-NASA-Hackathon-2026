extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var player: CharacterBody2D = $CharacterBody2d

var dialogue: CanvasLayer
var call_started := false


func _ready() -> void:
	dialogue = DialogueController.new()
	add_child(dialogue)
	dialogue.set_mission("Go to the Communications room.", $CommunicationsArea)
	$CommunicationsArea.body_entered.connect(_on_communications_area_body_entered)


func _on_communications_area_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D or call_started:
		return
	call_started = true
	Global.static_message_pending = false
	dialogue.set_mission("Answer the incoming crew call.")
	player.set_physics_process(false)
	var commander := Global.player_name if not Global.player_name.is_empty() else "Commander"
	await dialogue.say("Player", "Hello?")
	await dialogue.say(
		"Someone",
		"Good day, Commander %s. Your Crew Members are now on Earth; when will you be back?" % commander
	)
	await dialogue.say("Player", "I'll be back soon after I find the thing I am looking for.")
	await dialogue.say(
		"Someone",
		"Copy, Commander. Make sure to go to the Radiation Shield room during radiation events. It's intense here on Mars."
	)
	await dialogue.say("Player", "Copy.")
	await dialogue.say("Communications", "End call.")
	dialogue.set_mission("Return outside to the outpost.", $ExitMainDoor)
	player.set_physics_process(true)
