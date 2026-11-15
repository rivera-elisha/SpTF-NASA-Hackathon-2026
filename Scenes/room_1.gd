extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")
const InteractiveAssets = preload("res://Scripts/interactive_assets.gd")

@onready var game_over_panel: Panel = $CanvasLayer/GameOverPanel
@onready var player: CharacterBody2D = $CharacterBody2d

var dialogue: CanvasLayer
var visited_life_support := false
var visited_spacesuits := false
var can_exit := false
var dialogue_running := false
var donki_request: HTTPRequest
var nearby_life_support_monitor := false
var lab_analysis_visual: Node2D
var lab_pulse_elapsed := 0.0
var asset_dialogue_running := false
var interact_mgr: InteractiveAssets.InteractManager


func _ready() -> void:
	$CanvasLayer/DialoguePanel.hide()
	game_over_panel.hide()
	_configure_game_over_panel()
	$CanvasLayer/GameOverPanel/TryAgainButton.pressed.connect(_on_try_again_pressed)
	$CanvasLayer/GameOverPanel/ExitButton.pressed.connect(_on_exit_pressed)
	dialogue = DialogueController.new()
	add_child(dialogue)
	Global.radiation_warning_started.connect(_on_radiation_warning_started)
	Global.radiation_event_expired.connect(_on_radiation_event_expired)
	$LifeSupportMonitorArea.body_entered.connect(_on_life_support_monitor_entered)
	$LifeSupportMonitorArea.body_exited.connect(_on_life_support_monitor_exited)
	$MainLaboratoryArea.body_entered.connect(_on_main_laboratory_area_entered)
	_create_lab_analysis_visual()
	_update_lab_visual()
	_setup_room1_assets()
	visited_life_support = Global.life_support_checked
	visited_spacesuits = Global.spacesuits_checked
	can_exit = visited_life_support and visited_spacesuits
	$EquipmentArea.monitoring = Global.communication_call_completed and not Global.eva_equipment_obtained
	if $EquipmentArea.monitoring:
		$EquipmentArea.body_entered.connect(_on_equipment_area_body_entered)
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.", null)
	elif Global.part4_rocket_boarding_ready and not Global.part4_ending_reached:
		dialogue.set_mission("Return outside and board the rocket ship.", $ExitArea)
	elif Global.comms_static_part3_pending and not Global.comms_part3_arrived:
		dialogue.set_mission("Go to the Communication Room.", $ExitArea)
	elif Global.all_solar_panels_cleaned() and not Global.discovery_named:
		dialogue.set_mission(
			"Check the Main Laboratory Room for the unidentified sample.",
			$MainLaboratoryArea
		)
	elif Global.lab_analysis_started and not Global.all_solar_panels_cleaned():
		dialogue.set_mission(
			"Clean the solar panels outside (%d/2)." % Global.cleaned_solar_panel_ids.size(),
			$ExitArea
		)
	elif Global.glowing_object_collected and not Global.lab_analysis_started:
		dialogue.set_mission("Proceed to the Main Laboratory.", $MainLaboratoryArea)
	elif not visited_life_support:
		dialogue.set_mission("Check the life-support system.", $LifeSupportArea)
	elif not visited_spacesuits:
		dialogue.set_mission("Visit the Spacesuits room.", $SpacesuitsArea)
	elif Global.communication_call_completed and not Global.eva_equipment_obtained:
		dialogue.set_mission("Collect EVA equipment from storage.", $EquipmentArea)
	else:
		dialogue.set_mission("Proceed to the outpost Exit.", $ExitArea)
	if Global.radiation_warning_active:
		dialogue.show_radiation_warning()
	if Global.mission_complete:
		return
	donki_request = HTTPRequest.new()
	donki_request.timeout = 12.0
	add_child(donki_request)
	if not Global.room1_intro_seen:
		show_popup_sequence()


func _unhandled_input(event: InputEvent) -> void:
	if (
		not event.is_action_pressed("interact")
		or not nearby_life_support_monitor
		or dialogue_running
		or dialogue.game_over_visible
	):
		return
	get_viewport().set_input_as_handled()
	_open_life_support_monitor()


func _setup_room1_assets() -> void:
	interact_mgr = InteractiveAssets.create_interact_manager(
		self,
		player,
		func() -> bool:
			return dialogue_running or asset_dialogue_running or dialogue.is_busy() or dialogue.game_over_visible
	)

	var lsm := get_node_or_null("lifesupportmonitor") as Node2D
	if lsm:
		InteractiveAssets.attach_world_fx(self, lsm.global_position, "monitor_vitals", Vector2(72, 58))

	for suit_name in ["astronaut_suit_1", "astronaut_suit_2"]:
		var suit := get_node_or_null(suit_name) as Node2D
		if suit:
			InteractiveAssets.attach_world_fx(self, suit.global_position, "eva_suit", Vector2(46, 56))
			var s_pos := suit.global_position
			interact_mgr.add_interactable(
				suit_name,
				s_pos,
				"Inspect EMU Spacesuit",
				func() -> void: _inspect_eva_suit(s_pos, suit_name),
				72.0,
				Vector2(56, 62)
			)

	var eng := get_node_or_null("engine") as Node2D
	if eng:
		InteractiveAssets.attach_world_fx(self, eng.global_position, "reactor_engine", Vector2(68, 56))
		interact_mgr.add_interactable(
			"power_core",
			eng.global_position,
			"Check Power Core",
			func() -> void: _inspect_power_core(eng.global_position),
			78.0,
			Vector2(76, 66)
		)

	var mon2 := get_node_or_null("monitor2") as Node2D
	if mon2:
		InteractiveAssets.attach_world_fx(self, mon2.global_position, "monitor_radar", Vector2(62, 54))
		interact_mgr.add_interactable(
			"telemetry_console",
			mon2.global_position,
			"View Atmosphere Log",
			func() -> void: _inspect_atmosphere_log(mon2.global_position),
			76.0,
			Vector2(68, 58)
		)

	var scrubber := get_node_or_null("random_2") as Node2D
	if scrubber:
		InteractiveAssets.attach_world_fx(self, scrubber.global_position, "scrubber_panel", Vector2(68, 60))
		interact_mgr.add_interactable(
			"air_scrubber",
			scrubber.global_position,
			"Cycle O2 Scrubber",
			func() -> void: _cycle_air_scrubber(scrubber.global_position),
			78.0,
			Vector2(76, 68)
		)

	for ds_name in ["datastorage1", "datastorage2"]:
		var ds := get_node_or_null(ds_name) as Node2D
		if ds:
			InteractiveAssets.attach_world_fx(self, ds.global_position, "server_racks", Vector2(92, 84))
			var d_pos := ds.global_position
			interact_mgr.add_interactable(
				ds_name,
				d_pos,
				"Access Mission Archive",
				func() -> void: _inspect_data_archive(d_pos),
				84.0,
				Vector2(104, 96)
			)

	var lab_area := get_node_or_null("MainLaboratoryArea") as Node2D
	if lab_area:
		InteractiveAssets.attach_world_fx(self, lab_area.global_position, "glovebox", Vector2(88, 64))
		interact_mgr.add_interactable(
			"main_lab_bench",
			lab_area.global_position,
			"View Specimen Scan",
			func() -> void: _inspect_lab_specimen(lab_area.global_position),
			86.0,
			Vector2(96, 72),
			func() -> bool: return Global.discovery_named
		)


func _inspect_eva_suit(pos: Vector2, suit_id: String) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "scan", -9.0)
	InteractiveAssets.spawn_scan_beam_vfx(self, pos, Color(0.4, 0.92, 1.0, 0.9), 52.0, 62.0, 0.7)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.55, 0.95, 1.0, 0.85), 16, 62.0, 2.8)
	InteractiveAssets.spawn_floating_text(self, pos, "PLSS SEAL: 100%", Color(0.55, 0.96, 1.0))
	var label := "Unit A (Commander EVA Suit)" if suit_id == "astronaut_suit_1" else "Unit B (Reserve Exploration Suit)"
	var rad_note := "STORM SHIELDING: ELEVATED" if Global.radiation_warning_active else "Radiation Liner: Nominal"
	await dialogue.say("EMU Spacesuit Check", "%s — O2 Tanks: 98%% | Thermal Liquid Cooling: 21°C | %s." % [label, rad_note], 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _inspect_power_core(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "flame", -9.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(1.0, 0.68, 0.25, 0.92), 42.0, 0.45)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(1.0, 0.78, 0.35, 0.9), 20, 74.0, 3.0)
	var solar := "100% Optimal (Dust Cleared)" if Global.all_solar_panels_cleaned() else ("42% Output (Dusty Panels)" if Global.is_outpost_dusty() else "94% Nominal")
	InteractiveAssets.spawn_floating_text(self, pos, "SOLAR INPUT: " + ("100%" if Global.all_solar_panels_cleaned() else "NOMINAL"), Color(1.0, 0.85, 0.35))
	await dialogue.say("Outpost Power Core", "Solar Array Input: %s | Fuel Cell Backup: 96%% | Habitat Load: 3.4 kW." % solar, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _inspect_atmosphere_log(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "scan", -9.0)
	InteractiveAssets.spawn_scan_beam_vfx(self, pos, Color(0.35, 1.0, 0.55, 0.9), 58.0, 48.0, 0.65)
	InteractiveAssets.spawn_floating_text(self, pos, "MARS METEO UPDATED", Color(0.45, 1.0, 0.65))
	var dust_idx := "2.4 (Active Dust Storm Squall)" if Global.is_outpost_dusty() else "0.4 (Clear Martian Skies)"
	await dialogue.say("Mars Surface Meteorology", "External Temp: -63°C | Pressure: 6.1 mbar (CO2 95.3%%) | Dust Opacity Tau: %s." % dust_idx, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _cycle_air_scrubber(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "mist", -8.0)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.55, 0.96, 1.0, 0.9), 20, 70.0, 3.0)
	InteractiveAssets.spawn_floating_text(self, pos, "O2 PURGE: 99.6% PURE", Color(0.5, 0.98, 1.0))
	await dialogue.say("Sabatier Air Scrubber", "Zeolite CO2 scrubbers purged successfully. Cabin O2 partial pressure stabilized at 21.1 kPa.", 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _inspect_data_archive(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "interact", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(0.35, 0.88, 1.0, 0.9), 44.0, 0.45)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.4, 0.92, 1.0, 0.9), 20, 72.0, 3.0)
	InteractiveAssets.spawn_floating_text(self, pos, "ARCHIVE SYNCED", Color(0.5, 0.92, 1.0))
	var sample_note := "%d/7 basalt & regolith samples" % Global.rock_samples_collected
	var mat_note := Global.discovery_name if Global.discovery_named else "Pending Identification"
	await dialogue.say("Mission Data Archive", "Logged Geological Samples: %s | Priority Discovery: %s | DONKI Space Weather Feed: Online." % [sample_note, mat_note], 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _inspect_lab_specimen(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "success", -9.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(0.45, 0.95, 1.0, 0.95), 46.0, 0.5)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.6, 0.96, 1.0, 0.95), 24, 82.0, 3.4)
	InteractiveAssets.spawn_floating_text(self, pos, Global.discovery_name.to_upper(), Color(0.55, 0.98, 1.0))
	await dialogue.say("Main Laboratory Spectrometer", "Catalogued Discovery '%s': Luminescent Martian crystalline silicate exhibiting anomalous photonic resonance." % Global.discovery_name, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _open_life_support_monitor() -> void:
	player.set_physics_process(false)
	dialogue.set_interaction_hint("")
	var lsm := get_node_or_null("lifesupportmonitor") as Node2D
	if lsm:
		InteractiveAssets.play_sfx(self, "scan", -9.0)
		InteractiveAssets.spawn_ring_vfx(self, lsm.global_position, Color(0.32, 0.95, 1.0, 0.9), 42.0, 0.45)
		InteractiveAssets.spawn_scan_beam_vfx(self, lsm.global_position, Color(0.3, 1.0, 0.65, 0.9), 64.0, 56.0, 0.6)
	await dialogue.show_information("Life-Support Readings", Global.get_life_support_readings_text())
	player.set_physics_process(true)
	if nearby_life_support_monitor:
		dialogue.set_interaction_hint("Press E to check life-support and radiation levels")


func _on_life_support_monitor_entered(body: Node2D) -> void:
	if body != player:
		return
	nearby_life_support_monitor = true
	dialogue.set_interaction_hint("Press E to check life-support and radiation levels")


func _on_life_support_monitor_exited(body: Node2D) -> void:
	if body != player:
		return
	nearby_life_support_monitor = false
	dialogue.set_interaction_hint("")


func _configure_game_over_panel() -> void:
	game_over_panel.position = Vector2(356, 230)
	game_over_panel.size = Vector2(440, 190)
	var try_again: Button = $CanvasLayer/GameOverPanel/TryAgainButton
	try_again.text = "Try Again"
	try_again.position = Vector2(55, 115)
	try_again.size = Vector2(145, 44)
	var exit_button: Button = $CanvasLayer/GameOverPanel/ExitButton
	exit_button.text = "Exit"
	exit_button.position = Vector2(240, 115)
	exit_button.size = Vector2(145, 44)
	var title := Label.new()
	title.text = "GAME OVER"
	title.position = Vector2(0, 28)
	title.size = Vector2(440, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	game_over_panel.add_child(title)
	var detail := Label.new()
	detail.text = "You left before checking life support and spacesuits."
	detail.position = Vector2(12, 78)
	detail.size = Vector2(416, 28)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_panel.add_child(detail)


func show_dialogue(speaker: String, message: String, duration: float = 3.0) -> void:
	player.set_physics_process(false)
	await dialogue.say(speaker, message, duration)
	player.set_physics_process(true)


func show_popup_sequence() -> void:
	if dialogue_running or Global.room1_intro_seen:
		return
	dialogue_running = true
	Global.room1_intro_seen = true
	await show_dialogue("Welcome!", "Welcome to The Martian Outpost. Let's explore it!")
	await show_dialogue("Outpost Guide", "Let's get to know the main rooms within your outpost.")
	dialogue.set_mission("Check the life-support system.", $LifeSupportArea)
	await show_dialogue("Outpost Guide", "Go to the Life-support room and check its levels.")
	dialogue_running = false


func enter_life_support(body: Node2D) -> void:
	if not body is CharacterBody2D or visited_life_support or dialogue_running or Global.mission_complete:
		return
	visited_life_support = true
	Global.life_support_checked = true
	dialogue_running = true
	var oxygen := randi_range(85, 100)
	var co2 := randi_range(300, 1000)
	var temperature := randi_range(18, 25)
	await show_dialogue("Life-support System", "This is the life-support room. Check this occasionally, especially the radiation levels!")
	var radiation := await _fetch_radiation_level()
	Global.life_support_readings = {
		"oxygen": oxygen,
		"carbon_dioxide": co2,
		"temperature": temperature,
		"radiation": radiation
	}
	Global.save_mission_checkpoint("res://Scenes/Room_1.tscn")
	await show_dialogue(
		"System Readings",
		Global.get_life_support_readings_text(),
		6.0
	)
	dialogue.set_mission("Visit the Spacesuits room.", $SpacesuitsArea)
	await show_dialogue("Mission", "Go to the Spacesuits room, and proceed to the Exit.")
	dialogue_running = false


func _fetch_radiation_level() -> String:
	var now := int(Time.get_unix_time_from_system())
	var start_date := Time.get_datetime_dict_from_unix_time(now - 7 * 24 * 60 * 60)
	var start_string := "%04d-%02d-%02d" % [start_date.year, start_date.month, start_date.day]
	var end_string := Time.get_date_string_from_system()
	var url := "https://ccmc.gsfc.nasa.gov/DONKI-API/get/FLR?startDate=%s&endDate=%s" % [
		start_string, end_string
	]
	var request_error := donki_request.request(url, ["Accept: application/json"])
	if request_error != OK:
		push_error("Could not start NASA DONKI request: %s" % error_string(request_error))
		return "UNAVAILABLE (DONKI request could not start)"

	var response: Array = await donki_request.request_completed
	var response_code: int = response[1]
	if response[0] != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("NASA DONKI request failed (result %d, HTTP %d)." % [response[0], response_code])
		return "UNAVAILABLE (DONKI request failed)"

	var response_body: PackedByteArray = response[3]
	var events: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	if not events is Array:
		push_error("NASA DONKI returned an invalid solar-flare response.")
		return "UNAVAILABLE (invalid DONKI response)"
	for event in events:
		if event is Dictionary:
			var flare_class := str(event.get("classType", "")).to_upper()
			if flare_class.begins_with("M") or flare_class.begins_with("X"):
				return "HIGH (DONKI detected %s-class flare)" % flare_class
	return "LOW (no M/X-class flares reported in the past 7 days)"


func enter_spacesuits(body: Node2D) -> void:
	if not body is CharacterBody2D or visited_spacesuits or dialogue_running or Global.mission_complete:
		return
	visited_spacesuits = true
	Global.spacesuits_checked = true
	Global.save_mission_checkpoint("res://Scenes/Room_1.tscn")
	dialogue_running = true
	await show_dialogue("Spacesuits", "Spacesuit check complete. Your equipment is ready for an EVA.")
	can_exit = visited_life_support and visited_spacesuits
	dialogue.set_mission("Proceed to the outpost Exit.", $ExitArea)
	await show_dialogue("Mission", "Proceed to the Exit to explore the whole Mars Outpost.")
	dialogue_running = false


func enter_exit(body: Node2D) -> void:
	if not body is CharacterBody2D or dialogue_running:
		return
	if can_exit:
		Global.target_spawn_marker = &"MainBuildingOutsideSpawn"
		Global.target_spawn_position = Vector2.ZERO
		Global.player_facing_direction = "down"
		get_tree().call_deferred("change_scene_to_file", "res://Scenes/mars_map.tscn")
	else:
		game_over()


func _on_equipment_area_body_entered(body: Node2D) -> void:
	if body != player or dialogue_running or Global.eva_equipment_obtained:
		return
	Global.eva_equipment_obtained = true
	Global.save_mission_checkpoint(
		"res://Scenes/mars_map.tscn",
		&"MainBuildingOutsideSpawn"
	)
	dialogue_running = true
	player.set_physics_process(false)
	dialogue.set_mission("Return outside and continue the Rock Sample quest.", $ExitArea)
	await dialogue.notify_item("EVA Equipment")
	await dialogue.say("Storage", "Your EVA equipment is ready. You can begin the search outside.")
	player.set_physics_process(true)
	dialogue_running = false


func _process(delta: float) -> void:
	if is_instance_valid(lab_analysis_visual) and lab_analysis_visual.visible:
		lab_pulse_elapsed += delta
		var pulse := 0.8 + 0.2 * sin(lab_pulse_elapsed * 5.0)
		lab_analysis_visual.scale = Vector2.ONE * pulse
		lab_analysis_visual.modulate.a = 0.72 + 0.28 * sin(lab_pulse_elapsed * 4.0)


func _create_lab_analysis_visual() -> void:
	lab_analysis_visual = Node2D.new()
	lab_analysis_visual.name = "LabAnalysisVisual"
	lab_analysis_visual.position = Vector2(520, 65)
	lab_analysis_visual.z_index = 4

	var outer_glow := Polygon2D.new()
	outer_glow.polygon = PackedVector2Array([
		Vector2(-18, 0), Vector2(-13, -13), Vector2(0, -18),
		Vector2(13, -13), Vector2(18, 0), Vector2(13, 13),
		Vector2(0, 18), Vector2(-13, 13)
	])
	outer_glow.color = Color(0.35, 0.95, 1.0, 0.45)
	lab_analysis_visual.add_child(outer_glow)

	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([
		Vector2(-8, 0), Vector2(-5, -6), Vector2(0, -8),
		Vector2(6, -5), Vector2(8, 0), Vector2(5, 6),
		Vector2(0, 8), Vector2(-6, 5)
	])
	core.color = Color(0.75, 1.0, 0.95, 0.95)
	lab_analysis_visual.add_child(core)

	add_child(lab_analysis_visual)


func _update_lab_visual() -> void:
	if not is_instance_valid(lab_analysis_visual):
		return
	lab_analysis_visual.visible = Global.lab_analysis_started


func _on_main_laboratory_area_entered(body: Node2D) -> void:
	if body != player or dialogue_running or dialogue.game_over_visible:
		return
	if Global.glowing_object_collected and not Global.lab_analysis_started:
		dialogue_running = true
		Global.lab_analysis_started = true
		_update_lab_visual()
		InteractiveAssets.play_sfx(self, "scan", -8.0)
		InteractiveAssets.spawn_scan_beam_vfx(self, $MainLaboratoryArea.global_position, Color(0.4, 0.95, 1.0, 0.9), 76.0, 62.0, 0.85)
		InteractiveAssets.spawn_ring_vfx(self, $MainLaboratoryArea.global_position, Color(0.45, 0.95, 1.0, 0.9), 48.0, 0.55)
		InteractiveAssets.spawn_burst_vfx(self, $MainLaboratoryArea.global_position, Color(0.5, 0.96, 1.0, 0.9), 24, 78.0, 3.2)
		player.set_physics_process(false)
		await dialogue.say(
			"Main Laboratory",
			"The laboratory equipment has begun studying the unidentified object."
		)
		dialogue.set_mission("Clean the solar panels outside (0/2).", $ExitArea)
		await dialogue.say(
			"Mission",
			"While waiting for the findings on the unidentified object, clean the solar panels outside."
		)
		player.set_physics_process(true)
		dialogue_running = false
	elif Global.all_solar_panels_cleaned() and not Global.discovery_named:
		dialogue_running = true
		player.set_physics_process(false)
		var speaker: String = Global.get_player_display_name()
		await dialogue.say(
			speaker,
			"I can’t believe it… This is a huge discovery. I’m gonna name this..."
		)
		var chosen_name: String = await dialogue.prompt_text(
			"New Discovery on Mars",
			"Type a name of your choosing for this new discovery on Mars:",
			"Type discovery name..."
		)
		Global.discovery_name = chosen_name
		Global.discovery_named = true
		_update_lab_visual()
		InteractiveAssets.play_sfx(self, "success", -7.0)
		InteractiveAssets.spawn_ring_vfx(self, $MainLaboratoryArea.global_position, Color(0.55, 1.0, 0.78, 0.95), 54.0, 0.55)
		InteractiveAssets.spawn_burst_vfx(self, $MainLaboratoryArea.global_position, Color(0.5, 0.96, 1.0, 0.95), 32, 96.0, 3.6)
		InteractiveAssets.spawn_floating_text(self, $MainLaboratoryArea.global_position, "DISCOVERED: " + Global.discovery_name, Color(0.55, 1.0, 0.8), 1.5)
		await dialogue.say(
			speaker,
			"I can now go back on Earth to showcase %s." % Global.discovery_name
		)
		dialogue.play_static_sound()
		await dialogue.say(
			"Communications",
			"(Static sound) Static is coming from the Communications room..."
		)
		Global.comms_static_part3_pending = true
		dialogue.set_mission("Go to the Communication Room.", $ExitArea)
		await dialogue.say("Mission", "Go to the Communication Room.")
		player.set_physics_process(true)
		dialogue_running = false


func _on_radiation_warning_started() -> void:
	dialogue.show_radiation_warning()


func _on_radiation_event_expired() -> void:
	dialogue.show_game_over("How I wish I was able to find it... The radiation storm caught me outside.")


func game_over() -> void:
	player.set_physics_process(false)
	dialogue.hide_hud()
	game_over_panel.show()


func _on_try_again_pressed() -> void:
	Global.retry_from_last_completed_mission()


func _on_exit_pressed() -> void:
	get_tree().quit()
