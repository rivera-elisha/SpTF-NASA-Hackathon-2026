
extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")

@onready var map_sprite: Sprite2D = $Background
@onready var camera: Camera2D = $WorldObjects/CharacterBody2d/Camera2D
@onready var player: CharacterBody2D = $WorldObjects/CharacterBody2d

var dialogue: CanvasLayer
var rock_samples: Array[Area2D] = []
var glowing_object_area: Area2D
var glowing_pulse_elapsed := 0.0
var solar_panel_areas: Array[Area2D] = []
var dust_materials: Array[ShaderMaterial] = []
var solar_panels_material: ShaderMaterial
var part3_dialogue_running := false

const GLOWING_OBJECT_POSITION := Vector2(-220, 230)
const SOLAR_PANEL_POSITIONS: Array[Vector2] = [
	Vector2(537, -162),
	Vector2(537, -108)
]
const MARS_DUST_SHADER_CODE := """
shader_type canvas_item;

uniform float dust_top : hint_range(0.0, 1.0) = 0.0;
uniform float dust_bottom : hint_range(0.0, 1.0) = 0.0;
uniform float split_y : hint_range(0.0, 1.0) = 1.0;
uniform float pixel_density = 96.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a <= 0.01) {
		COLOR = tex;
	} else {
		float active_dust = (UV.y < split_y) ? dust_top : dust_bottom;
		vec2 grid_uv = floor(UV * pixel_density) / pixel_density;
		float clump = value_noise(grid_uv * 10.0);
		float fine = hash21(grid_uv * 43.0);
		float dust_mask = clamp((clump * 0.72 + fine * 0.35 - 0.18) * 1.35, 0.0, 1.0);
		vec3 mars_dust_dark = vec3(0.58, 0.25, 0.12);
		vec3 mars_dust_light = vec3(0.84, 0.45, 0.23);
		vec3 dust_col = mix(mars_dust_dark, mars_dust_light, smoothstep(0.35, 0.85, clump));
		float coat = active_dust * mix(0.28, 0.78, dust_mask);
		vec3 dirty_rgb = mix(tex.rgb * mix(1.0, 0.84, active_dust), dust_col, coat);
		COLOR = vec4(dirty_rgb, tex.a);
	}
}
"""

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

	_setup_mars_dust_materials()
	_create_rock_samples()
	_create_glowing_object()
	_create_solar_panel_areas()
	dialogue = DialogueController.new()
	add_child(dialogue)
	Global.radiation_warning_started.connect(_on_radiation_warning_started)
	Global.radiation_event_expired.connect(_on_radiation_event_expired)
	_update_dust_visuals()
	_refresh_rock_samples()
	_refresh_glowing_object()
	_refresh_solar_panel_areas()
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
		return
	if Global.comms_part3_arrived:
		dialogue.set_mission("Communications Room reached. Standby for incoming message.")
	elif Global.comms_static_part3_pending or Global.discovery_named:
		dialogue.set_mission("Go to the Communication Room.", $WorldObjects/SafetyBuilding/PersonalDoor)
	elif Global.all_solar_panels_cleaned() and not Global.discovery_named:
		dialogue.set_mission(
			"Check the Main Laboratory Room for the unidentified sample.",
			$WorldObjects/MainBuilding/MainDoor
		)
	elif Global.lab_analysis_started and not Global.all_solar_panels_cleaned():
		dialogue.set_mission(
			"Clean the solar panels outside (%d/2)." % Global.cleaned_solar_panel_ids.size(),
			_get_next_dirty_solar_panel()
		)
	elif Global.glowing_object_collected and not Global.lab_analysis_started:
		dialogue.set_mission("Proceed to the Main Laboratory.", $WorldObjects/MainBuilding/MainDoor)
	elif Global.rock_samples_collected >= 7 and not Global.glowing_object_collected:
		dialogue.set_mission("Check the glowing light.", glowing_object_area)
		if not Global.glow_spotted:
			Global.glow_spotted = true
			player.set_physics_process(false)
			await dialogue.say("Mission", "A mysterious glow can be seen nearby. Check the glowing light.")
			player.set_physics_process(true)
	elif Global.radiation_shelter_complete and not Global.greenhouse_visited:
		dialogue.set_mission("Return to the Safety Building and visit the Greenhouse.", $WorldObjects/SafetyBuilding/PersonalDoor)
	elif Global.greenhouse_visited and Global.rock_samples_collected == 6:
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
		Global.glow_spotted = true
		_refresh_glowing_object()
		part3_dialogue_running = true
		player.set_physics_process(false)
		dialogue.set_mission("Check the glowing light.", glowing_object_area)
		await dialogue.say("Mission", "All seven Rock Samples collected! A mysterious glow can be seen nearby.")
		await dialogue.say("Mission", "Check the glowing light.")
		player.set_physics_process(true)
		part3_dialogue_running = false
	else:
		dialogue.set_mission(
			"Collect Rock Samples: %d/7." % Global.rock_samples_collected,
			_get_next_rock_sample()
		)


func _process(delta: float) -> void:
	if is_instance_valid(glowing_object_area) and glowing_object_area.visible:
		glowing_pulse_elapsed += delta
		var outer_ring := glowing_object_area.get_node_or_null("OuterGlow") as Polygon2D
		var inner_ring := glowing_object_area.get_node_or_null("InnerGlow") as Polygon2D
		var core := glowing_object_area.get_node_or_null("Core") as Polygon2D
		if outer_ring != null:
			var s := 0.88 + 0.24 * sin(glowing_pulse_elapsed * 4.2)
			outer_ring.scale = Vector2.ONE * s
			outer_ring.color.a = 0.25 + 0.16 * sin(glowing_pulse_elapsed * 4.2)
		if inner_ring != null:
			var s2 := 0.92 + 0.15 * cos(glowing_pulse_elapsed * 5.6)
			inner_ring.scale = Vector2.ONE * s2
		if core != null:
			core.rotation = glowing_pulse_elapsed * 0.9


func _setup_mars_dust_materials() -> void:
	var shader := Shader.new()
	shader.code = MARS_DUST_SHADER_CODE

	var dusty_targets := [
		[$WorldObjects/MainBuilding/PixelArtMarsOutpostMainBuilding, 96.0],
		[$WorldObjects/SafetyBuilding/FuturisticSafetyBuildingPixelArt, 96.0],
		[$WorldObjects/PersonalBuilding/PersonalBuildingHabitatModule, 96.0],
		[$WorldObjects/GarageBuilding/NewgarageEdited, 96.0],
		[$WorldObjects/Rocket/SciFiRocketLaunchPlatform, 96.0],
		[$WorldObjects/Rocket/SymmetricalPixelArtRocketSpritesheet, 96.0],
		[$WorldObjects/Newmarsrover, 48.0]
	]

	for entry in dusty_targets:
		var sprite := entry[0] as Sprite2D
		if sprite == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("split_y", 1.0)
		mat.set_shader_parameter("pixel_density", entry[1])
		sprite.material = mat
		dust_materials.append(mat)

	var solar_sprite := $WorldObjects/Newsolarpanels as Sprite2D
	if solar_sprite != null:
		solar_panels_material = ShaderMaterial.new()
		solar_panels_material.shader = shader
		solar_panels_material.set_shader_parameter("split_y", 0.5)
		solar_panels_material.set_shader_parameter("pixel_density", 56.0)
		solar_sprite.material = solar_panels_material


func _update_dust_visuals() -> void:
	var dusty: bool = Global.is_outpost_dusty()
	var building_dust := 1.0 if dusty else 0.0
	for mat in dust_materials:
		mat.set_shader_parameter("dust_top", building_dust)
	if solar_panels_material != null:
		var top_dust := 1.0 if (dusty and not Global.cleaned_solar_panel_ids.has(0)) else 0.0
		var bottom_dust := 1.0 if (dusty and not Global.cleaned_solar_panel_ids.has(1)) else 0.0
		solar_panels_material.set_shader_parameter("dust_top", top_dust)
		solar_panels_material.set_shader_parameter("dust_bottom", bottom_dust)


func _create_glowing_object() -> void:
	glowing_object_area = Area2D.new()
	glowing_object_area.name = "GlowingObject"
	glowing_object_area.position = GLOWING_OBJECT_POSITION
	glowing_object_area.monitoring = false
	glowing_object_area.visible = false

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(56, 48)
	collision.shape = shape
	glowing_object_area.add_child(collision)

	var outer_glow := Polygon2D.new()
	outer_glow.name = "OuterGlow"
	outer_glow.polygon = PackedVector2Array([
		Vector2(-32, 0), Vector2(-23, -23), Vector2(0, -32),
		Vector2(23, -23), Vector2(32, 0), Vector2(23, 23),
		Vector2(0, 32), Vector2(-23, 23)
	])
	outer_glow.color = Color(0.32, 0.96, 1.0, 0.32)
	glowing_object_area.add_child(outer_glow)

	var inner_glow := Polygon2D.new()
	inner_glow.name = "InnerGlow"
	inner_glow.polygon = PackedVector2Array([
		Vector2(-19, 0), Vector2(-13, -13), Vector2(0, -19),
		Vector2(13, -13), Vector2(19, 0), Vector2(13, 13),
		Vector2(0, 19), Vector2(-13, 13)
	])
	inner_glow.color = Color(0.55, 1.0, 0.88, 0.65)
	glowing_object_area.add_child(inner_glow)

	var core := Polygon2D.new()
	core.name = "Core"
	core.polygon = PackedVector2Array([
		Vector2(-9, 0), Vector2(-4, -9), Vector2(4, -9),
		Vector2(9, 0), Vector2(4, 9), Vector2(-4, 9)
	])
	core.color = Color(0.95, 1.0, 0.72, 1.0)
	glowing_object_area.add_child(core)

	$WorldObjects.add_child(glowing_object_area)
	glowing_object_area.body_entered.connect(_on_glowing_object_entered)


func _refresh_glowing_object() -> void:
	if not is_instance_valid(glowing_object_area):
		return
	var active: bool = Global.rock_samples_collected >= 7 and not Global.glowing_object_collected
	glowing_object_area.visible = active
	glowing_object_area.set_deferred("monitoring", active)


func _on_glowing_object_entered(body: Node2D) -> void:
	if body != player or part3_dialogue_running or Global.glowing_object_collected:
		return
	if Global.rock_samples_collected < 7:
		return
	Global.glowing_object_collected = true
	part3_dialogue_running = true
	_refresh_glowing_object()
	player.set_physics_process(false)
	dialogue.notify_item("Unidentified Object")
	await dialogue.say(
		Global.get_player_display_name(),
		"This is what I’m looking for! This would be legendary for Science!"
	)
	dialogue.set_mission("Proceed to the Main Laboratory.", $WorldObjects/MainBuilding/MainDoor)
	await dialogue.say("Mission", "Proceed to the Main Laboratory.")
	player.set_physics_process(true)
	part3_dialogue_running = false


func _create_solar_panel_areas() -> void:
	var container := Node2D.new()
	container.name = "SolarPanelCleaningAreas"
	$WorldObjects.add_child(container)
	for index in range(SOLAR_PANEL_POSITIONS.size()):
		var area := Area2D.new()
		area.name = "SolarPanelArea%d" % (index + 1)
		area.position = SOLAR_PANEL_POSITIONS[index]
		area.monitoring = false

		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(160, 64)
		collision.shape = shape
		area.add_child(collision)

		var highlight := Polygon2D.new()
		highlight.name = "DirtyHighlight"
		highlight.polygon = PackedVector2Array([
			Vector2(-48, -18), Vector2(48, -18),
			Vector2(48, 18), Vector2(-48, 18)
		])
		highlight.color = Color(0.95, 0.58, 0.25, 0.22)
		highlight.visible = false
		area.add_child(highlight)

		container.add_child(area)
		area.body_entered.connect(_on_solar_panel_area_entered.bind(index))
		solar_panel_areas.append(area)


func _refresh_solar_panel_areas() -> void:
	var cleaning_active: bool = Global.lab_analysis_started and not Global.all_solar_panels_cleaned()
	for index in range(solar_panel_areas.size()):
		var area := solar_panel_areas[index]
		var needs_cleaning: bool = cleaning_active and not Global.cleaned_solar_panel_ids.has(index)
		area.set_deferred("monitoring", needs_cleaning)
		var highlight := area.get_node_or_null("DirtyHighlight") as Polygon2D
		if highlight != null:
			highlight.visible = needs_cleaning


func _get_next_dirty_solar_panel() -> Area2D:
	for index in range(solar_panel_areas.size()):
		if not Global.cleaned_solar_panel_ids.has(index):
			return solar_panel_areas[index]
	return null


func _on_solar_panel_area_entered(body: Node2D, panel_id: int) -> void:
	if body != player or not Global.lab_analysis_started:
		return
	if Global.cleaned_solar_panel_ids.has(panel_id):
		return
	Global.cleaned_solar_panel_ids.append(panel_id)
	_refresh_solar_panel_areas()
	_tween_solar_panel_clean(panel_id)
	_spawn_clean_flash(SOLAR_PANEL_POSITIONS[panel_id])

	if Global.all_solar_panels_cleaned():
		part3_dialogue_running = true
		player.set_physics_process(false)
		dialogue.notify_item("Solar Panels Cleaned (2/2)")
		await get_tree().create_timer(0.4).timeout
		dialogue.set_mission(
			"Check the Main Laboratory Room for the unidentified sample.",
			$WorldObjects/MainBuilding/MainDoor
		)
		await dialogue.say(
			"Mission",
			"Let’s now check the Main Laboratory Room for the unidentified sample."
		)
		player.set_physics_process(true)
		part3_dialogue_running = false
	else:
		dialogue.set_mission(
			"Clean the solar panels outside (%d/2)." % Global.cleaned_solar_panel_ids.size(),
			_get_next_dirty_solar_panel()
		)
		dialogue.notify_item("Solar Panel Cleaned (%d/2)" % Global.cleaned_solar_panel_ids.size())


func _tween_solar_panel_clean(panel_id: int) -> void:
	if solar_panels_material == null:
		return
	var param_name := "dust_top" if panel_id == 0 else "dust_bottom"
	var tween := create_tween()
	tween.tween_method(
		func(value: float) -> void:
			solar_panels_material.set_shader_parameter(param_name, value),
		1.0,
		0.0,
		0.38
	)


func _spawn_clean_flash(world_pos: Vector2) -> void:
	var sparkle := Polygon2D.new()
	sparkle.position = world_pos
	sparkle.polygon = PackedVector2Array([
		Vector2(-24, 0), Vector2(-6, -6), Vector2(0, -24),
		Vector2(6, -6), Vector2(24, 0), Vector2(6, 6),
		Vector2(0, 24), Vector2(-6, 6)
	])
	sparkle.color = Color(0.75, 0.96, 1.0, 0.9)
	$WorldObjects.add_child(sparkle)
	var tween := create_tween()
	tween.tween_property(sparkle, "scale", Vector2(1.5, 1.5), 0.35)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 0.35)
	await tween.finished
	if is_instance_valid(sparkle):
		sparkle.queue_free()
