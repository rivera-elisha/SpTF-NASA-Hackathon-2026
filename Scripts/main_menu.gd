extends Control

@export_file("*.tscn") var start_scene_path: String = "res://Scenes/choose_gender.tscn"

@onready var start_button: Button = $VBoxContainer/Button
@onready var exit_button: Button = $VBoxContainer/Button2


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	exit_button.pressed.connect(_on_exit_pressed)


func _on_start_pressed() -> void:
	Global.reset_mission()
	Global.target_spawn_marker = &""
	Global.target_spawn_position = Vector2.ZERO
	Global.player_facing_direction = "down"

	var error := get_tree().change_scene_to_file(start_scene_path)
	if error != OK:
		push_error("Failed to load start scene: " + start_scene_path)


func _on_exit_pressed() -> void:
	get_tree().quit()
