
extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var map_sprite: Sprite2D = $Background
@onready var camera: Camera2D = $WorldObjects/CharacterBody2d/Camera2D
@onready var player: CharacterBody2D = $WorldObjects/CharacterBody2d

var dialogue: CanvasLayer
var rock_samples: Array[Area2D] = []

const ROCK_SAMPLE_POSITIONS: Array[Vector2] = [
	Vector2(-42, 170),
	Vector2(56, 205),
	Vector2(160, 170),
	Vector2(245, 240),
	Vector2(-78, 280),
	Vector2(72, 330),
	Vector2(225, 340)
]


func _ready() -> void:
	if map_sprite == null:
		push_error("Background Sprite2D not found.")
		return
	if camera == null:
		push_error("Player Camera2D not found.")
		return
	var map_bounds: Rect2 = map_sprite.get_global_transform() * map_sprite.get_rect()
	camera.limit_left = floori(map_bounds.position.x)
	camera.limit_top = floori(map_bounds.position.y)
	camera.limit_right = ceili(map_bounds.end.x)
	camera.limit_bottom = ceili(map_bounds.end.y)

	_create_rock_samples()
	dialogue = DialogueController.new()
	add_child(dialogue)
	Global.radiation_warning_started.connect(_on_radiation_warning_started)
	Global.radiation_event_expired.connect(_on_radiation_event_expired)
	_refresh_rock_samples()
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
		return
	if Global.radiation_shelter_complete and not Global.greenhouse_visited:
		dialogue.set_mission("Return to the Safety Building and visit the Greenhouse.", $WorldObjects/SafetyBuilding/PersonalDoor)
	elif Global.greenhouse_visited and Global.rock_samples_collected >= 6:
		dialogue.set_mission(
			"Collect the final Rock Sample (%d/7)." % Global.rock_samples_collected,
			_get_next_rock_sample()
		)
		if not Global.rock_search_briefing_seen:
			Global.rock_search_briefing_seen = true
			player.set_physics_process(false)
			await dialogue.say("Mission", "Return outside and collect the final Rock Sample.")
			player.set_physics_process(true)
	elif Global.communication_call_completed and not Global.eva_equipment_obtained:
		dialogue.set_mission("Go to the Main Building storage room for EVA equipment.", $WorldObjects/MainBuilding/MainDoor)
		if not Global.eva_briefing_seen:
			Global.eva_briefing_seen = true
			player.set_physics_process(false)
			await dialogue.say(
				"Mission",
				"Perform an EVA operation—Extravehicular Activity—outside the outpost. Collect seven Rock Samples."
			)
			await dialogue.say("Mission", "Go to the storage room in Room 1 for your other equipment.")
			player.set_physics_process(true)
	elif Global.eva_equipment_obtained and not Global.radiation_shelter_complete:
		if not Global.did_exercise:
			player.set_physics_process(false)
			await dialogue.say("Player", "How I wish I had trained before coming outside...")
			dialogue.show_game_over("You skipped exercise and could not survive the EVA search.")
			return
		Global.eva_search_started = true
		Global.rock_collection_started = true
		_refresh_rock_samples()
		if Global.rock_samples_collected < 6:
			dialogue.set_mission(
				"Collect Rock Samples: %d/7." % Global.rock_samples_collected,
				_get_next_rock_sample()
			)
		elif Global.radiation_warning_active:
			dialogue.set_mission("6/7 Rock Samples. URGENT: Reach the Radiation Room.", $WorldObjects/SafetyBuilding/PersonalDoor)
			dialogue.show_radiation_warning()
		else:
			dialogue.set_mission("Collect Rock Samples: %d/7." % Global.rock_samples_collected, null)
		if not Global.rock_search_briefing_seen:
			Global.rock_search_briefing_seen = true
			player.set_physics_process(false)
			await dialogue.say("Mission", "Your EVA equipment is ready. Collect seven Rock Samples around the outpost.")
			player.set_physics_process(true)
	elif Global.static_message_pending:
		dialogue.set_mission("Find the Communications room.", $WorldObjects/SafetyBuilding/PersonalDoor)
		player.set_physics_process(false)
		await dialogue.say(
			"Communications",
			"(Static sound) It seems someone is messaging you in the Communications room. Go to the other room outside."
		)
		player.set_physics_process(true)
	elif not Global.map_intro_shown:
		Global.map_intro_shown = true
		dialogue.set_mission("Explore the Personal Building and find the Exercise Room.", $WorldObjects/PersonalBuilding/ExerciseDoor)
		player.set_physics_process(false)
		await dialogue.say("Outpost Guide", "This is your whole Mars Outpost. Proceed to the other rooms and find the exercise room.")
		await dialogue.say("Outpost Guide", "The Exercise Room is in the Personal Building.")
		player.set_physics_process(true)
	else:
		dialogue.set_mission("Explore the outpost.", $WorldObjects/MainBuilding/MainDoor)


func _on_radiation_warning_started() -> void:
	dialogue.show_radiation_warning()
	dialogue.set_mission("6/7 Rock Samples. URGENT: Reach the Radiation Room.", $WorldObjects/SafetyBuilding/PersonalDoor)


func _on_radiation_event_expired() -> void:
	dialogue.show_game_over("How I wish I was able to find it... The radiation storm caught me outside.")


func _create_rock_samples() -> void:
	var sample_container := Node2D.new()
	sample_container.name = "RockSamples"
	$WorldObjects.add_child(sample_container)
	for index in range(ROCK_SAMPLE_POSITIONS.size()):
		var sample := Area2D.new()
		sample.name = "RockSample%d" % (index + 1)
		sample.position = ROCK_SAMPLE_POSITIONS[index]
		sample.monitoring = false
		sample.visible = false
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(48, 40)
		collision.shape = shape
		sample.add_child(collision)
		var marker := Polygon2D.new()
		marker.polygon = PackedVector2Array([
			Vector2(-25, 0), Vector2(-18, -18), Vector2(0, -25),
			Vector2(18, -18), Vector2(25, 0), Vector2(18, 18),
			Vector2(0, 25), Vector2(-18, 18)
		])
		marker.color = Color(0.35, 0.9, 1.0, 0.32)
		sample.add_child(marker)
		var rock := Polygon2D.new()
		rock.polygon = PackedVector2Array([
			Vector2(-22, 8), Vector2(-17, -8), Vector2(-7, -15),
			Vector2(6, -12), Vector2(20, -3), Vector2(23, 8),
			Vector2(14, 14), Vector2(-14, 14)
		])
		rock.color = Color("9b8064") if index % 2 == 0 else Color("ad8b68")
		sample.add_child(rock)
		var small_rock := Polygon2D.new()
		small_rock.position = Vector2(20, 10)
		small_rock.polygon = PackedVector2Array([
			Vector2(-8, 3), Vector2(-5, -5), Vector2(3, -7),
			Vector2(9, -1), Vector2(7, 5), Vector2(-3, 7)
		])
		small_rock.color = Color("c2a17a")
		sample.add_child(small_rock)
		sample_container.add_child(sample)
		sample.body_entered.connect(_on_rock_sample_area_entered.bind(index))
		rock_samples.append(sample)


func _refresh_rock_samples() -> void:
	for index in range(rock_samples.size()):
		var is_final_sample := (
			index == 6
			and Global.rock_samples_collected == 6
			and Global.radiation_shelter_complete
			and Global.greenhouse_visited
		)
		var is_initial_sample := index < 6 and Global.rock_samples_collected < 6
		var available := (
			Global.rock_collection_started
			and not Global.mission_complete
			and not Global.collected_rock_sample_ids.has(index)
			and (is_initial_sample or is_final_sample)
		)
		rock_samples[index].visible = available
		rock_samples[index].set_deferred("monitoring", available)


func _get_next_rock_sample() -> Area2D:
	for sample in rock_samples:
		if sample.visible:
			return sample
	return null


func _on_rock_sample_area_entered(body: Node2D, sample_id: int) -> void:
	if body != player or not Global.rock_collection_started or Global.collected_rock_sample_ids.has(sample_id):
		return
	if sample_id == 6:
		if (
			Global.rock_samples_collected != 6
			or not Global.radiation_shelter_complete
			or not Global.greenhouse_visited
		):
			return
	elif Global.rock_samples_collected >= 6:
		return
	Global.collected_rock_sample_ids.append(sample_id)
	Global.rock_samples_collected += 1
	_refresh_rock_samples()
	dialogue.notify_item("Rock Sample")
	if Global.rock_samples_collected == 6:
		dialogue.set_mission("RADIATION ALERT: Reach the Radiation Room now.", $WorldObjects/SafetyBuilding/PersonalDoor)
		Global.start_radiation_event()
	elif Global.rock_samples_collected == 7:
		Global.mission_complete = true
		player.set_physics_process(false)
		dialogue.set_mission("Rock Sample collection complete: 7/7.", null)
		await dialogue.say("Mission", "All seven Rock Samples collected. Mission complete.")
		player.set_physics_process(true)
	else:
		dialogue.set_mission(
			"Collect Rock Samples: %d/7." % Global.rock_samples_collected,
			_get_next_rock_sample()
		)
