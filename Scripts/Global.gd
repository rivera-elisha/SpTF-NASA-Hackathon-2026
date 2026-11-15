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
var mission_complete: bool = false
var life_support_readings: Dictionary = {}
var radiation_deadline_msec: int = 0
var _radiation_event_generation: int = 0


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
	mission_complete = false
	life_support_readings.clear()
	radiation_deadline_msec = 0
	_radiation_event_generation += 1


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
