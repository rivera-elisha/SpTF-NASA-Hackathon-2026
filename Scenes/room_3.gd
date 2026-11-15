extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var player: CharacterBody2D = $CharacterBody2d

var dialogue: CanvasLayer
var call_started := false
var greenhouse_dialogue_running := false
var comms_part3_running := false


func _ready() -> void:
	dialogue = DialogueController.new()
	add_child(dialogue)
	Global.radiation_warning_started.connect(_on_radiation_warning_started)
	Global.radiation_event_sheltered.connect(_on_radiation_event_sheltered)
	Global.radiation_event_expired.connect(_on_radiation_event_expired)
	$RadiationShelterArea.body_entered.connect(_on_radiation_shelter_area_entered)
	$GreenhouseArea.body_entered.connect(_on_greenhouse_area_entered)
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
		return
	if Global.radiation_warning_active:
		dialogue.set_mission("6/7 Rock Samples. URGENT: Reach the Radiation Room.", $RadiationShelterArea)
		dialogue.show_radiation_warning(true)
		dialogue.clear_sandstorm()
		if $RadiationShelterArea.overlaps_body(player):
			Global.try_enter_radiation_shelter()
	elif Global.comms_part3_arrived:
		dialogue.set_mission("Communications Room reached. Standby for incoming message.")
	elif Global.comms_static_part3_pending or Global.discovery_named:
		dialogue.set_mission("Go to the Communication Room.", $CommunicationsArea)
		$CommunicationsArea.body_entered.connect(_on_communications_part3_entered)
	elif Global.all_solar_panels_cleaned():
		dialogue.set_mission("Return outside and check the Main Laboratory Room.", $ExitMainDoor)
	elif Global.lab_analysis_started:
		dialogue.set_mission(
			"Return outside and clean the solar panels (%d/2)." % Global.cleaned_solar_panel_ids.size(),
			$ExitMainDoor
		)
	elif Global.glowing_object_collected:
		dialogue.set_mission("Return outside and proceed to the Main Laboratory.", $ExitMainDoor)
	elif Global.rock_samples_collected >= 7:
		dialogue.set_mission("Return outside and check the glowing light.", $ExitMainDoor)
	elif Global.radiation_shelter_complete and not Global.greenhouse_visited:
		dialogue.set_mission("Proceed to the Greenhouse room.", $GreenhouseArea)
	elif Global.greenhouse_visited:
		dialogue.set_mission("Go outside and collect the final Rock Sample.", $ExitMainDoor)
	elif Global.communication_call_completed:
		dialogue.set_mission("Return outside and begin the Rock Sample quest.", $ExitMainDoor)
	else:
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
	Global.communication_call_completed = true
	dialogue.set_mission("Return outside to collect EVA equipment from storage.", $ExitMainDoor)
	await dialogue.say("Mission", "The call is complete. Collect your EVA equipment from the storage room.")
	player.set_physics_process(true)


func _on_radiation_warning_started() -> void:
	dialogue.show_radiation_warning(true)
	dialogue.clear_sandstorm()
	dialogue.set_mission("6/7 Rock Samples. URGENT: Reach the Radiation Room.", $RadiationShelterArea)
	if $RadiationShelterArea.overlaps_body(player):
		Global.try_enter_radiation_shelter()


func _on_radiation_shelter_area_entered(body: Node2D) -> void:
	if body == player:
		Global.try_enter_radiation_shelter()


func _on_radiation_event_sheltered() -> void:
	dialogue.clear_radiation_warning()
	player.set_physics_process(false)
	await dialogue.say("Player", "The radiation levels are falling. I'm safe in the Radiation Room.")
	await dialogue.say(
		"Life-Support Readings",
		Global.get_life_support_readings_text(),
		3.0
	)
	await dialogue.say("Mission", "The radiation event has passed. Proceed to the Greenhouse.")
	dialogue.set_mission("Proceed to the Greenhouse room.", $GreenhouseArea)
	player.set_physics_process(true)


func _on_radiation_event_expired() -> void:
	dialogue.show_game_over("How I wish I was able to find it... The radiation storm caught me outside.")


func _on_greenhouse_area_entered(body: Node2D) -> void:
	if (
		body != player
		or greenhouse_dialogue_running
		or not Global.radiation_shelter_complete
		or Global.greenhouse_visited
	):
		return
	greenhouse_dialogue_running = true
	Global.greenhouse_visited = true
	player.set_physics_process(false)
	await dialogue.say("Greenhouse", "This is the Greenhouse room where you can plant.")
	await dialogue.say("Greenhouse", "Your crew members already planted some tomatoes. They will be ready to harvest some time.")
	await dialogue.say("Mission", "You can now go outside and collect the final Rock Sample.")
	dialogue.set_mission("Go outside and collect the final Rock Sample.", $ExitMainDoor)
	player.set_physics_process(true)


func _on_communications_part3_entered(body: Node2D) -> void:
	if body != player or comms_part3_running or Global.comms_part3_arrived:
		return
	if not Global.comms_static_part3_pending and not Global.discovery_named:
		return
	comms_part3_running = true
	Global.comms_part3_arrived = true
	player.set_physics_process(false)
	dialogue.play_static_sound()
	await dialogue.say(
		"Communications",
		"(Static sound) Static crackles across the communications terminal..."
	)
	dialogue.set_mission("Communications Room reached. Standby for incoming message.")
	player.set_physics_process(true)
	comms_part3_running = false
