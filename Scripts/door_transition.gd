
extends Area2D

@export_file("*.tscn") var destination_scene_path: String = ""
@export var destination_spawn_marker: StringName = &"InteriorEntrySpawn"
@export_enum("down", "up", "left", "right") var arrival_facing: String = "up"

var transition_started := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Only allow the player to activate the door
	if transition_started or not body is CharacterBody2D:
		return

	if destination_scene_path.is_empty():
		push_error("Door transition has no destination scene!")
		return

	transition_started = true

	# Save the destination spawn information
	Global.target_spawn_marker = destination_spawn_marker
	Global.target_spawn_position = Vector2.ZERO
	Global.player_facing_direction = arrival_facing

	# Change scenes safely
	call_deferred("_change_scene")


func _change_scene() -> void:
	var error = get_tree().change_scene_to_file(destination_scene_path)

	if error != OK:
		transition_started = false
		Global.target_spawn_marker = &""
		push_error("Failed to load scene: " + destination_scene_path)
