extends Node

var target_spawn_position: Vector2 = Vector2.ZERO
var target_spawn_marker: StringName = &""

var player_facing_direction: String = "down"
var player_gender: String = ""
var player_name: String = ""
var movement_speed_multiplier: float = 1.0
var static_message_pending: bool = false
var map_intro_shown: bool = false


func reset_mission() -> void:
	movement_speed_multiplier = 1.0
	static_message_pending = false
	map_intro_shown = false
