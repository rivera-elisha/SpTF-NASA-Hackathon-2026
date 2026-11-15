extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var game_over_panel: Panel = $CanvasLayer/GameOverPanel
@onready var player: CharacterBody2D = $CharacterBody2d

var dialogue: CanvasLayer
var visited_life_support := false
var visited_spacesuits := false
var can_exit := false
var dialogue_running := false
var donki_request: HTTPRequest


func _ready() -> void:
	$CanvasLayer/DialoguePanel.hide()
	game_over_panel.hide()
	_configure_game_over_panel()
	$CanvasLayer/GameOverPanel/TryAgainButton.pressed.connect(_on_try_again_pressed)
	$CanvasLayer/GameOverPanel/ExitButton.pressed.connect(_on_exit_pressed)
	dialogue = DialogueController.new()
	add_child(dialogue)
	visited_life_support = Global.life_support_checked
	visited_spacesuits = Global.spacesuits_checked
	can_exit = visited_life_support and visited_spacesuits
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.", null)
	elif not visited_life_support:
		dialogue.set_mission("Check the life-support system.", $LifeSupportArea)
	elif not visited_spacesuits:
		dialogue.set_mission("Visit the Spacesuits room.", $SpacesuitsArea)
	else:
		dialogue.set_mission("Proceed to the outpost Exit.", $ExitArea)
	if Global.mission_complete:
		return
	donki_request = HTTPRequest.new()
	donki_request.timeout = 12.0
	add_child(donki_request)
	if not Global.room1_intro_seen:
		show_popup_sequence()


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
	await show_dialogue(
		"System Readings",
		"Oxygen Level: %d%%\nCarbon Dioxide Level: %d ppm\nTemperature: %d°C\nRadiation Level: %s" % [
			oxygen, co2, temperature, radiation
		],
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


func game_over() -> void:
	player.set_physics_process(false)
	dialogue.hide_hud()
	game_over_panel.show()


func _on_try_again_pressed() -> void:
	Global.reset_mission()
	get_tree().reload_current_scene()


func _on_exit_pressed() -> void:
	get_tree().quit()
