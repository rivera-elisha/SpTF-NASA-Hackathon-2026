extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var player: CharacterBody2D = $CharacterBody2d

var dialogue: CanvasLayer
var call_started := false
var greenhouse_dialogue_running := false
var comms_part3_running := false
var asset_dialogue_running := false
var interact_mgr: InteractiveAssets.InteractManager
var monitor_fx: Node2D
var phone_fx: Node2D


func _ready() -> void:
	dialogue = DialogueController.new()
	add_child(dialogue)
	Global.radiation_warning_started.connect(_on_radiation_warning_started)
	Global.radiation_event_sheltered.connect(_on_radiation_event_sheltered)
	Global.radiation_event_expired.connect(_on_radiation_event_expired)
	$RadiationShelterArea.body_entered.connect(_on_radiation_shelter_area_entered)
	$GreenhouseArea.body_entered.connect(_on_greenhouse_area_entered)
	_setup_room3_assets()
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
		return
	if Global.radiation_warning_active:
		dialogue.set_mission("6/7 Rock Samples. URGENT: Reach the Radiation Room.", $RadiationShelterArea)
		dialogue.show_radiation_warning(true)
		dialogue.clear_sandstorm()
		if $RadiationShelterArea.overlaps_body(player):
			Global.try_enter_radiation_shelter()
	elif Global.part4_rocket_boarding_ready and not Global.part4_ending_reached:
		dialogue.set_mission("Go outside to the rocket ship cockpit.", $ExitMainDoor)
	elif Global.comms_part3_arrived and Global.part4_choice.is_empty():
		dialogue.set_mission("Use the Communications Room terminal.", $CommunicationsArea)
		$CommunicationsArea.body_entered.connect(_on_communications_part3_entered)
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


func _setup_room3_assets() -> void:
	interact_mgr = InteractiveAssets.create_interact_manager(
		self,
		player,
		func() -> bool:
			return (
				dialogue.is_busy()
				or greenhouse_dialogue_running
				or comms_part3_running
				or asset_dialogue_running
			)
	)

	var gh := get_node_or_null("greenhouse") as Node2D
	if gh:
		InteractiveAssets.attach_world_fx(self, gh.global_position, "greenhouse", Vector2(124, 68))
		interact_mgr.add_interactable(
			"greenhouse_rack",
			gh.global_position,
			"Tend Hydroponic Crops",
			func() -> void: _on_interact_greenhouse(gh.global_position),
			106.0,
			Vector2(142, 84),
			func() -> bool: return Global.greenhouse_visited or not Global.radiation_shelter_complete
		)

	var mon := get_node_or_null("monitor") as Node2D
	if mon:
		monitor_fx = InteractiveAssets.attach_world_fx(self, mon.global_position, "monitor_radar", Vector2(120, 84))
		monitor_fx.set_meta("urgent_mode", (Global.comms_static_part3_pending or Global.discovery_named) and Global.part4_choice.is_empty())
		interact_mgr.add_interactable(
			"comms_radar",
			mon.global_position,
			"Scan Deep-Space Radar",
			func() -> void: _on_interact_comms_monitor(mon.global_position),
			96.0,
			Vector2(138, 102),
			func() -> bool: return Global.communication_call_completed and (Global.part4_choice != "" or not Global.discovery_named)
		)

	var tel := get_node_or_null("telephone") as Node2D
	if tel:
		phone_fx = InteractiveAssets.attach_world_fx(self, tel.global_position, "comms_phone", Vector2(96, 72))
		phone_fx.set_meta("urgent_mode", (Global.comms_static_part3_pending or Global.discovery_named) and Global.part4_choice.is_empty())
		interact_mgr.add_interactable(
			"earth_transceiver",
			tel.global_position,
			"Inspect Earth Transceiver",
			func() -> void: _on_interact_telephone(tel.global_position),
			104.0,
			Vector2(160, 92),
			func() -> bool: return Global.communication_call_completed and (Global.part4_choice != "" or not Global.discovery_named)
		)

	var rad_unit := get_node_or_null("random1") as Node2D
	if rad_unit:
		InteractiveAssets.attach_world_fx(self, rad_unit.global_position, "scrubber_panel", Vector2(78, 72))
		interact_mgr.add_interactable(
			"radiation_array",
			rad_unit.global_position,
			"Check Bunker Shielding",
			func() -> void: _on_interact_shield_console(rad_unit.global_position),
			100.0,
			Vector2(106, 98)
		)


func _on_interact_greenhouse(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "mist", -8.0)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.55, 1.0, 0.72, 0.9), 22, 68.0, 3.0)
	InteractiveAssets.spawn_floating_text(self, pos, "CROPS WATERED: +O2", Color(0.55, 1.0, 0.7))
	await dialogue.say("Hydroponic Greenhouse", "LED purple/white spectrum arrays nourishing dwarf tomatoes & kale. Fresh crops scrub excess CO2 and boost crew morale.", 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_comms_monitor(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "scan", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(0.35, 1.0, 0.58, 0.92), 48.0, 0.48)
	InteractiveAssets.spawn_scan_beam_vfx(self, pos, Color(0.35, 1.0, 0.58, 0.9), 112.0, 80.0, 0.7)
	InteractiveAssets.spawn_floating_text(self, pos, "DSN LINK: 214M KM", Color(0.5, 1.0, 0.68))
	var interference := "Heavy dust-storm multipath interference detected." if Global.is_outpost_dusty() else "Clear X-Band telemetry lock with Earth DSN Goldstone."
	await dialogue.say("Deep-Space Comms Radar", "Mars-to-Earth Round-Trip Signal Delay: 14m 22s. Status: %s" % interference, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_telephone(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "interact", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(0.45, 0.92, 1.0, 0.9), 44.0, 0.45)
	InteractiveAssets.spawn_floating_text(self, pos, "ENCRYPTED LOGS READY", Color(0.6, 0.95, 1.0))
	var hr_note := "Last Earth message indicated unusual static interference during transmission." if Global.part4_choice == "leave_mars" else "Earth downlink channel idle."
	await dialogue.say("Earth Transceiver Deck", "High-Gain Antenna Transceiver. %s" % hr_note, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_shield_console(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "heal", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(0.38, 0.92, 1.0, 0.92), 44.0, 0.48)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.48, 0.95, 1.0, 0.9), 18, 66.0, 3.0)
	InteractiveAssets.spawn_floating_text(self, pos, "SHIELDING: 100% SEALED", Color(0.5, 0.96, 1.0))
	var storm := "ACTIVE SOLAR EVENT CONTAINED" if Global.radiation_warning_active else "NOMINAL COSMIC RAY BLOCKING"
	await dialogue.say("Safety Bunker Shielding Array", "High-density polyethylene & water-wall storm shelter shielding active. Current Status: %s." % storm, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


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
	InteractiveAssets.play_sfx(self, "mist", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, $GreenhouseArea.global_position, Color(0.45, 1.0, 0.65, 0.9), 48.0, 0.5)
	InteractiveAssets.spawn_burst_vfx(self, $GreenhouseArea.global_position, Color(0.55, 1.0, 0.72, 0.9), 24, 72.0, 3.2)
	player.set_physics_process(false)
	await dialogue.say("Greenhouse", "This is the Greenhouse room where you can plant.")
	await dialogue.say("Greenhouse", "Your crew members already planted some tomatoes. They will be ready to harvest some time.")
	await dialogue.say("Mission", "You can now go outside and collect the final Rock Sample.")
	dialogue.set_mission("Go outside and collect the final Rock Sample.", $ExitMainDoor)
	player.set_physics_process(true)


func _on_communications_part3_entered(body: Node2D) -> void:
	if (
		body != player
		or comms_part3_running
		or Global.mission_complete
		or not Global.part4_choice.is_empty()
	):
		return
	if not Global.comms_static_part3_pending and not Global.discovery_named:
		return
	comms_part3_running = true
	Global.comms_part3_arrived = true
	player.set_physics_process(false)
	await _run_part4_communications()


func _run_part4_communications() -> void:
	var speaker: String = Global.get_player_display_name()
	dialogue.play_static_sound()
	await dialogue.say(
		speaker,
		"I have good news! I can now go back to Earth after my personal mission has been accomplished."
	)
	dialogue.play_static_sound()
	await dialogue.say(
		"Astronaut HR",
		"Commander, we had data here on Earth that there would be a disastrous— (static: communication delay due to dust storms)."
	)
	var leave_mars: bool = await dialogue.choose(
		"Mission",
		"You need to choose: fix the Communications Room to know what Astronaut HR is about to say, or go to the cockpit and leave Mars immediately.",
		"Leave Mars",
		"Fix Communications Room",
		true
	)
	if leave_mars:
		Global.part4_choice = "leave_mars"
		Global.part4_rocket_boarding_ready = true
		await dialogue.say(speaker, "I'm going to the cockpit to leave Mars immediately.")
		dialogue.set_mission("Go outside to the rocket ship cockpit.", $ExitMainDoor)
		await dialogue.say("Mission", "Proceed outside to the rocket ship and leave Mars.")
		player.set_physics_process(true)
		comms_part3_running = false
		return

	Global.part4_choice = "fix_comms"
	Global.part4_ending_reached = true
	Global.mission_complete = true
	dialogue.set_mission("Fix the Communications Room.")
	dialogue.play_static_sound(0.8)
	if is_instance_valid(monitor_fx):
		monitor_fx.set_meta("urgent_mode", false)
	if is_instance_valid(phone_fx):
		phone_fx.set_meta("urgent_mode", false)
	InteractiveAssets.spawn_ring_vfx(self, $CommunicationsArea.global_position, Color(1.0, 0.55, 0.25, 0.92), 48.0, 0.55)
	InteractiveAssets.spawn_burst_vfx(self, $CommunicationsArea.global_position, Color(1.0, 0.72, 0.3, 0.95), 26, 86.0, 3.2)
	await dialogue.say("Communications", "Repairing communications relay and filtering dust storm interference...", 0.0)
	await get_tree().create_timer(1.5).timeout
	dialogue.hide_dialogue()
	await dialogue.say("Astronaut HR", "It's better for you to stay there for a while.")
	await dialogue.say(speaker, "What do you mean?")
	await dialogue.say(
		"Astronaut HR",
		"You’re already on Mars, where it's peaceful. Why would you want to go back here?"
	)
	await dialogue.say(speaker, "…")
	await dialogue.say(speaker, "BRING ME BACK!")
	await dialogue.show_static_screen(2.0)
	comms_part3_running = false
	await dialogue.show_end_credits(
		"ENDING 1 OF 2 — STATIC ON MARS",
		"You repaired the Communications Room, only to be left behind in silence.",
		"Outcome: Remaining on Mars Outpost"
	)
