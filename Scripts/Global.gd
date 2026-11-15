extends Node

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
var mission_complete: bool = false


func reset_mission() -> void:
	movement_speed_multiplier = 1.0
	static_message_pending = false
	map_intro_shown = false
	room1_intro_seen = false
	life_support_checked = false
	spacesuits_checked = false
	exercise_prompt_completed = false
	communication_call_completed = false
	mission_complete = false
