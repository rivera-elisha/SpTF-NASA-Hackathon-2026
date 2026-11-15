extends Node

signal radiation_warning_started
signal radiation_event_sheltered
signal radiation_event_expired

var target_spawn_position: Vector2 = Vector2.ZERO
var target_spawn_marker: StringName = &""

var player_facing_direction: String = "down"
var player_gender: String = ""
var player_name: String = ""
var movement_speed_multiplier: float = 1.0
var static_message_pending: bool = false
var map_intro_shown: bool = false
var room1_intro_seen: bool = false
var life_support_checked: bool = false
var spacesuits_checked: bool = false
var exercise_prompt_completed: bool = false
var communication_call_completed: bool = false
var did_exercise: bool = false
var eva_equipment_obtained: bool = false
var eva_search_started: bool = false
var rock_collection_started: bool = false
var rock_samples_collected: int = 0
var collected_rock_sample_ids: Array[int] = []
var radiation_event_started: bool = false
var radiation_warning_active: bool = false
var radiation_shelter_complete: bool = false
var greenhouse_visited: bool = false
var eva_briefing_seen: bool = false
var rock_search_briefing_seen: bool = false
var glow_spotted: bool = false
var glowing_object_collected: bool = false
var lab_analysis_started: bool = false
var cleaned_solar_panel_ids: Array[int] = []
var discovery_named: bool = false
var discovery_name: String = ""
var comms_static_part3_pending: bool = false
var comms_part3_arrived: bool = false
var part4_choice: String = ""
var part4_rocket_boarding_ready: bool = false
var part4_ending_reached: bool = false
var mission_complete: bool = false
var life_support_readings: Dictionary = {}
var radiation_deadline_msec: int = 0
var _radiation_event_generation: int = 0
var checkpoint_scene_path := ""
var checkpoint_spawn_marker: StringName = &""
var checkpoint_state: Dictionary = {}

const CHECKPOINT_FIELDS := [
	"movement_speed_multiplier",
	"static_message_pending",
	"map_intro_shown",
	"room1_intro_seen",
	"life_support_checked",
	"spacesuits_checked",
	"exercise_prompt_completed",
	"communication_call_completed",
	"did_exercise",
	"eva_equipment_obtained",
	"eva_search_started",
	"rock_collection_started",
	"rock_samples_collected",
	"collected_rock_sample_ids",
	"radiation_event_started",
	"radiation_warning_active",
	"radiation_shelter_complete",
	"greenhouse_visited",
	"eva_briefing_seen",
	"rock_search_briefing_seen",
	"glow_spotted",
	"glowing_object_collected",
	"lab_analysis_started",
	"cleaned_solar_panel_ids",
	"discovery_named",
	"discovery_name",
	"comms_static_part3_pending",
	"comms_part3_arrived",
	"part4_choice",
	"part4_rocket_boarding_ready",
	"part4_ending_reached",
	"mission_complete",
	"life_support_readings",
]


func reset_mission() -> void:
	movement_speed_multiplier = 1.0
	static_message_pending = false
	map_intro_shown = false
	room1_intro_seen = false
	life_support_checked = false
	spacesuits_checked = false
	exercise_prompt_completed = false
	communication_call_completed = false
	did_exercise = false
	eva_equipment_obtained = false
	eva_search_started = false
	rock_collection_started = false
	rock_samples_collected = 0
	collected_rock_sample_ids.clear()
	radiation_event_started = false
	radiation_warning_active = false
	radiation_shelter_complete = false
	greenhouse_visited = false
	eva_briefing_seen = false
	rock_search_briefing_seen = false
	glow_spotted = false
	glowing_object_collected = false
	lab_analysis_started = false
	cleaned_solar_panel_ids.clear()
	discovery_named = false
	discovery_name = ""
	comms_static_part3_pending = false
	comms_part3_arrived = false
	part4_choice = ""
	part4_rocket_boarding_ready = false
	part4_ending_reached = false
	mission_complete = false
	life_support_readings.clear()
	radiation_deadline_msec = 0
	_radiation_event_generation += 1
	target_spawn_marker = &""
	target_spawn_position = Vector2.ZERO
	player_facing_direction = "down"
	checkpoint_state.clear()
	save_mission_checkpoint("res://Scenes/Room_1.tscn")


func save_mission_checkpoint(scene_path: String, spawn_marker: StringName = &"") -> void:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("Cannot save mission checkpoint for missing scene: %s" % scene_path)
		return
	checkpoint_scene_path = scene_path
	checkpoint_spawn_marker = spawn_marker
	checkpoint_state.clear()
	for field in CHECKPOINT_FIELDS:
		var field_name := StringName(field)
		var value: Variant = get(field_name)
		if value is Array or value is Dictionary:
			checkpoint_state[field_name] = value.duplicate(true)
		else:
			checkpoint_state[field_name] = value


func retry_from_last_completed_mission() -> void:
	if checkpoint_scene_path.is_empty() or checkpoint_state.is_empty():
		push_error("No completed mission checkpoint is available for retry.")
		get_tree().reload_current_scene()
		return
	for field in CHECKPOINT_FIELDS:
		var field_name := StringName(field)
		if not checkpoint_state.has(field_name):
			push_error("Mission checkpoint is missing progress field: %s" % field_name)
			return
		var value: Variant = checkpoint_state[field_name]
		if value is Array or value is Dictionary:
			value = value.duplicate(true)
		set(field_name, value)
	radiation_deadline_msec = 0
	_radiation_event_generation += 1
	target_spawn_marker = checkpoint_spawn_marker
	target_spawn_position = Vector2.ZERO
	player_facing_direction = "down"
	var error := get_tree().change_scene_to_file(checkpoint_scene_path)
	if error != OK:
		push_error("Could not load mission checkpoint scene '%s': %s" % [
			checkpoint_scene_path,
			error_string(error)
		])


func get_player_display_name() -> String:
	return player_name if not player_name.is_empty() else "Player"


func all_solar_panels_cleaned() -> bool:
	return cleaned_solar_panel_ids.size() >= 2


func is_outpost_dusty() -> bool:
	return radiation_shelter_complete


func start_radiation_event() -> void:
	if mission_complete or radiation_event_started or rock_samples_collected < 6 or not did_exercise:
		return
	radiation_event_started = true
	_radiation_event_generation += 1
	radiation_warning_active = true
	radiation_deadline_msec = Time.get_ticks_msec() + 10000
	radiation_warning_started.emit()
	_run_radiation_event(_radiation_event_generation)


func _run_radiation_event(generation: int) -> void:
	await get_tree().create_timer(10.0).timeout
	if generation != _radiation_event_generation:
		return
	if radiation_warning_active:
		radiation_warning_active = false
		radiation_event_expired.emit()


func try_enter_radiation_shelter() -> bool:
	if not radiation_warning_active or radiation_shelter_complete:
		return false
	radiation_warning_active = false
	radiation_shelter_complete = true
	radiation_event_sheltered.emit()
	return true


func radiation_seconds_remaining() -> int:
	return maxi(0, ceili(float(radiation_deadline_msec - Time.get_ticks_msec()) / 1000.0))


func get_life_support_readings_text() -> String:
	if life_support_readings.is_empty():
		return "Life-support readings are unavailable."
	var outpost_radiation := "NORMAL"
	if radiation_warning_active:
		outpost_radiation = "HIGH — seek shelter immediately"
	elif radiation_shelter_complete:
		outpost_radiation = "LOW — radiation event has passed"
	return "Oxygen: %s%%\nCarbon dioxide: %s ppm\nTemperature: %s°C\nRadiation Level (DONKI): %s\nOutpost Radiation: %s" % [
		life_support_readings.get("oxygen", "N/A"),
		life_support_readings.get("carbon_dioxide", "N/A"),
		life_support_readings.get("temperature", "N/A"),
		life_support_readings.get("radiation", "UNAVAILABLE"),
		outpost_radiation
	]
