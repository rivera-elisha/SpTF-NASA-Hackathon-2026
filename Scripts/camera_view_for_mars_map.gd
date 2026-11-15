
extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")
const InteractiveAssets = preload("res://Scripts/interactive_assets.gd")
const PowerWashMinigame = preload("res://Scripts/powerwash_minigame.gd")

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
var rocket_boarding_area: Area2D
var rocket_launch_running := false
var asset_dialogue_running := false
var interact_mgr: InteractiveAssets.InteractManager
var solar_glint_fx: Node2D
var rocket_cryo_fx: Node2D
var powerwash_overlay: PowerWashMinigame

const GLOWING_OBJECT_POSITION := Vector2(-220, 230)
const ROCKET_BOARDING_POSITION := Vector2(330, 152)
const ROCKET_HATCH_POSITION := Vector2(330, 54)
const AWARD_CEREMONY_SCENE := "res://Scenes/award_ceremony.tscn"
const ROCKET_ANIMATION_PATHS: Array[String] = [
	"res://Assets/rocket animations/Pixel Rocket with Smaller Flames.png",
	"res://Assets/rocket animations/Rocket With Flickering Exhaust Flames.png",
	"res://Assets/rocket animations/Detailed Orange-and-White Rocket Vector.png",
	"res://Assets/rocket animations/Dynamic Pixel Rocket with Segmented Flames.png"
]
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
	_create_rocket_boarding_area()
	dialogue = DialogueController.new()
	add_child(dialogue)
	Global.radiation_warning_started.connect(_on_radiation_warning_started)
	Global.radiation_event_expired.connect(_on_radiation_event_expired)
	_update_dust_visuals()
	_refresh_rock_samples()
	_refresh_glowing_object()
	_refresh_solar_panel_areas()
	_refresh_rocket_boarding_area()
	_setup_mars_assets()
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
		return
	if Global.part4_rocket_boarding_ready and not Global.part4_ending_reached:
		dialogue.set_mission("Board the rocket ship to leave Mars.", rocket_boarding_area)
	elif Global.comms_part3_arrived and Global.part4_choice.is_empty():
		dialogue.set_mission("Go to the Communication Room.", $WorldObjects/SafetyBuilding/PersonalDoor)
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
	var picked_gpos := rock_samples[sample_id].global_position if sample_id < rock_samples.size() else player.global_position
	InteractiveAssets.play_sfx(self, "pickup", -9.0)
	InteractiveAssets.spawn_ring_vfx(self, picked_gpos, Color(0.95, 0.72, 0.35, 0.92), 34.0, 0.42)
	InteractiveAssets.spawn_burst_vfx(self, picked_gpos, Color(0.92, 0.56, 0.3, 0.9), 18, 70.0, 3.0)
	InteractiveAssets.spawn_floating_text(self, picked_gpos, "ROCK SAMPLE %d/7" % Global.rock_samples_collected, Color(1.0, 0.88, 0.55))
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
	if is_instance_valid(rocket_boarding_area) and rocket_boarding_area.visible:
		glowing_pulse_elapsed += delta
		var beacon := rocket_boarding_area.get_node_or_null("BoardingBeacon") as Polygon2D
		if beacon != null:
			var pulse := 0.88 + 0.16 * sin(glowing_pulse_elapsed * 4.5)
			beacon.scale = Vector2.ONE * pulse
			beacon.color.a = 0.28 + 0.16 * sin(glowing_pulse_elapsed * 4.5)


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
	var glow_gpos := glowing_object_area.global_position if is_instance_valid(glowing_object_area) else player.global_position
	InteractiveAssets.play_sfx(self, "success", -7.0)
	InteractiveAssets.spawn_ring_vfx(self, glow_gpos, Color(0.45, 0.96, 1.0, 0.96), 56.0, 0.55)
	InteractiveAssets.spawn_burst_vfx(self, glow_gpos, Color(0.6, 0.98, 1.0, 0.96), 34, 102.0, 3.6)
	InteractiveAssets.spawn_floating_text(self, glow_gpos, "UNIDENTIFIED SAMPLE!", Color(0.6, 0.98, 1.0), 1.4)
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
	if is_instance_valid(solar_glint_fx):
		var dusty: bool = Global.is_outpost_dusty()
		solar_glint_fx.set_meta("dirty_top", dusty and not Global.cleaned_solar_panel_ids.has(0))
		solar_glint_fx.set_meta("dirty_bottom", dusty and not Global.cleaned_solar_panel_ids.has(1))


func _get_next_dirty_solar_panel() -> Area2D:
	for index in range(solar_panel_areas.size()):
		if not Global.cleaned_solar_panel_ids.has(index):
			return solar_panel_areas[index]
	return null


func _on_solar_panel_area_entered(body: Node2D, panel_id: int) -> void:
	if body != player or not Global.lab_analysis_started or part3_dialogue_running:
		return
	if Global.cleaned_solar_panel_ids.has(panel_id):
		return
	if powerwash_overlay != null:
		return
	open_powerwash_minigame(panel_id)


func open_powerwash_minigame(panel_id: int) -> void:
	if powerwash_overlay != null or Global.cleaned_solar_panel_ids.has(panel_id):
		return
	part3_dialogue_running = true
	player.set_physics_process(false)

	var pw := PowerWashMinigame.new()
	powerwash_overlay = pw
	add_child(pw)
	pw.start_for_panel(panel_id)

	pw.washed_progress.connect(func(pid: int, pct: float) -> void:
		if solar_panels_material != null:
			var param_name := "dust_top" if pid == 0 else "dust_bottom"
			solar_panels_material.set_shader_parameter(param_name, clampf(1.0 - pct, 0.0, 1.0))
	)

	pw.cancelled.connect(func(pid: int) -> void:
		if solar_panels_material != null and not Global.cleaned_solar_panel_ids.has(pid):
			var param_name := "dust_top" if pid == 0 else "dust_bottom"
			solar_panels_material.set_shader_parameter(param_name, 1.0 if Global.is_outpost_dusty() else 0.0)
		if is_instance_valid(powerwash_overlay):
			powerwash_overlay.queue_free()
			powerwash_overlay = null
		player.set_physics_process(true)
		part3_dialogue_running = false
	)

	pw.completed.connect(func(pid: int) -> void:
		if is_instance_valid(powerwash_overlay):
			powerwash_overlay.queue_free()
			powerwash_overlay = null
		await complete_solar_panel_clean(pid)
	)


func complete_solar_panel_clean(panel_id: int) -> void:
	if not Global.cleaned_solar_panel_ids.has(panel_id):
		Global.cleaned_solar_panel_ids.append(panel_id)
	_refresh_solar_panel_areas()
	_tween_solar_panel_clean(panel_id)
	var local_pos := SOLAR_PANEL_POSITIONS[panel_id]
	_spawn_clean_flash(local_pos)
	var world_p := ($WorldObjects as Node2D).to_global(local_pos)
	InteractiveAssets.play_sfx(self, "success", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, world_p, Color(0.55, 0.96, 1.0, 0.95), 44.0, 0.5)
	InteractiveAssets.spawn_burst_vfx(self, world_p, Color(0.7, 0.96, 1.0, 0.95), 26, 86.0, 3.2)
	InteractiveAssets.spawn_floating_text(self, world_p, "PANEL %d CLEANED!" % (panel_id + 1), Color(0.55, 0.98, 1.0))

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
		player.set_physics_process(true)
		part3_dialogue_running = false


func _setup_mars_assets() -> void:
	interact_mgr = InteractiveAssets.create_interact_manager(
		self,
		player,
		func() -> bool:
			return (
				dialogue.is_busy()
				or part3_dialogue_running
				or rocket_launch_running
				or asset_dialogue_running
				or powerwash_overlay != null
			)
	)

	var rover := get_node_or_null("WorldObjects/Newmarsrover") as Node2D
	if rover:
		InteractiveAssets.attach_world_fx(self, rover.global_position, "mars_rover", Vector2(72, 64))
		interact_mgr.add_interactable(
			"mars_rover",
			rover.global_position,
			"Scan with Mars Rover",
			func() -> void: _on_interact_mars_rover(rover.global_position),
			86.0,
			Vector2(78, 76)
		)

	var garage := get_node_or_null("WorldObjects/GarageBuilding") as Node2D
	if garage:
		var hangar_door_pos := garage.global_position + Vector2(0, -14)
		var g_beacon := InteractiveAssets.attach_world_fx(self, hangar_door_pos, "building_beacon", Vector2(24, 24))
		g_beacon.set_meta("dusty_mode", Global.is_outpost_dusty())
		interact_mgr.add_interactable(
			"eva_garage",
			hangar_door_pos,
			"Inspect EVA Garage",
			func() -> void: _on_interact_garage(hangar_door_pos),
			92.0,
			Vector2(118, 64)
		)

	for door_path in [
		"WorldObjects/MainBuilding/MainDoor",
		"WorldObjects/SafetyBuilding/PersonalDoor",
		"WorldObjects/PersonalBuilding/ExerciseDoor"
	]:
		var door := get_node_or_null(door_path) as Node2D
		if door:
			var b := InteractiveAssets.attach_world_fx(self, door.global_position + Vector2(26, -12), "building_beacon", Vector2(18, 18))
			b.set_meta("dusty_mode", Global.is_outpost_dusty())

	var panels := get_node_or_null("WorldObjects/Newsolarpanels") as Node2D
	if panels:
		solar_glint_fx = InteractiveAssets.attach_world_fx(self, panels.global_position, "solar_panel_glint", Vector2(96, 86))
		_refresh_solar_panel_areas()
		for idx in SOLAR_PANEL_POSITIONS.size():
			var p_idx := idx
			var p_world := ($WorldObjects as Node2D).to_global(SOLAR_PANEL_POSITIONS[idx])
			interact_mgr.add_interactable(
				"powerwash_panel_%d" % p_idx,
				p_world,
				"PowerWash Solar Panel %d/2" % (p_idx + 1),
				func() -> void: open_powerwash_minigame(p_idx),
				72.0,
				Vector2(88, 42),
				func() -> bool: return Global.lab_analysis_started and not Global.cleaned_solar_panel_ids.has(p_idx)
			)
		interact_mgr.add_interactable(
			"solar_array_inspect",
			panels.global_position,
			"Inspect Solar Array Output",
			func() -> void: _on_interact_solar_panels(panels.global_position),
			92.0,
			Vector2(102, 98),
			func() -> bool: return not Global.lab_analysis_started or Global.all_solar_panels_cleaned()
		)

	var rocket_sprite := get_node_or_null("WorldObjects/Rocket/SymmetricalPixelArtRocketSpritesheet") as Node2D
	if rocket_sprite:
		rocket_cryo_fx = InteractiveAssets.attach_world_fx(self, rocket_sprite.global_position + Vector2(0, 26), "rocket_cryo", Vector2(68, 86))
		rocket_cryo_fx.set_meta("rocket_ready", Global.part4_rocket_boarding_ready and not Global.part4_ending_reached)


func _on_interact_mars_rover(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "scan", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(0.42, 0.94, 1.0, 0.92), 48.0, 0.5)
	InteractiveAssets.spawn_scan_beam_vfx(self, pos, Color(1.0, 0.35, 0.28, 0.9), 74.0, 68.0, 0.7)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.95, 0.55, 0.32, 0.85), 16, 62.0, 2.8)
	InteractiveAssets.spawn_floating_text(self, pos, "MASTCAM-Z: ONLINE", Color(0.55, 0.96, 1.0))
	var anom := "Strange bioluminescent trace logged to SW quadrant." if Global.glow_spotted or Global.glowing_object_collected else "Perimeter geological sweep ongoing."
	await dialogue.say(
		"Autonomous Mars Rover",
		"Wheel Traction: Nominal | Battery Reserve: 89%% | Basalt Cores Analyzed: %d/7 | %s" % [Global.rock_samples_collected, anom],
		0.0
	)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_garage(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "interact", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(1.0, 0.76, 0.3, 0.9), 44.0, 0.45)
	InteractiveAssets.spawn_floating_text(self, pos, "BAY AIRLOCK: SEALED", Color(1.0, 0.85, 0.4))
	var dust_note := "External dust seal engaged due to storm." if Global.is_outpost_dusty() else "Standby for rover battery docking."
	await dialogue.say("EVA Garage & Hangar Bay", "Pressurized maintenance bay holding spare rover mesh wheels, nitrogen purge cylinders, and high-pressure powerwasher gear. %s" % dust_note, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_solar_panels(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "scan", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(0.5, 0.95, 1.0, 0.9), 48.0, 0.45)
	var msg := (
		"Photovoltaic Arrays washed clean! Generating 100% power output (8.4 kW)."
		if Global.all_solar_panels_cleaned()
		else "Photovoltaic Arrays generating baseline power (8.2 kW). Regular dust cleaning keeps life-support nominal."
	)
	InteractiveAssets.spawn_floating_text(self, pos, "SOLAR: 8.4 KW" if Global.all_solar_panels_cleaned() else "SOLAR: NOMINAL", Color(0.6, 0.98, 1.0))
	await dialogue.say("Mars Solar Farm", msg, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


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


func _create_rocket_boarding_area() -> void:
	rocket_boarding_area = Area2D.new()
	rocket_boarding_area.name = "RocketBoardingArea"
	rocket_boarding_area.position = ROCKET_BOARDING_POSITION
	rocket_boarding_area.monitoring = false
	rocket_boarding_area.visible = false

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(150, 88)
	collision.shape = shape
	rocket_boarding_area.add_child(collision)

	var beacon := Polygon2D.new()
	beacon.name = "BoardingBeacon"
	beacon.polygon = PackedVector2Array([
		Vector2(-32, 0), Vector2(0, -18), Vector2(32, 0), Vector2(0, 18)
	])
	beacon.color = Color(0.45, 0.92, 1.0, 0.36)
	rocket_boarding_area.add_child(beacon)

	$WorldObjects.add_child(rocket_boarding_area)
	rocket_boarding_area.body_entered.connect(_on_rocket_boarding_area_entered)


func _refresh_rocket_boarding_area() -> void:
	if not is_instance_valid(rocket_boarding_area):
		return
	var active := Global.part4_rocket_boarding_ready and not Global.part4_ending_reached and not rocket_launch_running
	rocket_boarding_area.visible = active
	rocket_boarding_area.set_deferred("monitoring", active)


func _on_rocket_boarding_area_entered(body: Node2D) -> void:
	if (
		body != player
		or rocket_launch_running
		or not Global.part4_rocket_boarding_ready
		or Global.part4_ending_reached
	):
		return
	rocket_launch_running = true
	Global.part4_ending_reached = true
	_refresh_rocket_boarding_area()
	await _play_rocket_launch_cutscene()


func _play_rocket_launch_cutscene() -> void:
	player.set_physics_process(false)
	dialogue.set_hud_visible(false)
	dialogue.clear_radiation_warning()
	if is_instance_valid(rocket_cryo_fx):
		rocket_cryo_fx.visible = false
	player.z_index = 10

	await _walk_player_to_rocket_hatch()

	var rocket_sprite := $WorldObjects/Rocket/SymmetricalPixelArtRocketSpritesheet as Sprite2D
	if rocket_sprite == null:
		await dialogue.fade_to_black(0.8)
		get_tree().change_scene_to_file(AWARD_CEREMONY_SCENE)
		return
	rocket_sprite.z_index = 12

	var rocket_frames: Array[Texture2D] = []
	for path in ROCKET_ANIMATION_PATHS:
		var tex := load(path) as Texture2D
		if tex != null:
			rocket_frames.append(tex)

	var pad_dust := _create_launch_particles(
		"PadDustParticles",
		Vector2(330, 126),
		120.0,
		45.0,
		125.0,
		6.0,
		15.0,
		Color("e39660"),
		Color("9f4722", 0.0),
		Vector2(0, -16),
		46,
		1.05
	)
	var exhaust_smoke := _create_launch_particles(
		"RocketExhaustSmoke",
		rocket_sprite.position + Vector2(0, 124),
		46.0,
		70.0,
		155.0,
		7.0,
		17.0,
		Color("fff2cc"),
		Color("b8b8c2", 0.0),
		Vector2(0, 42),
		56,
		0.85
	)
	$WorldObjects/Rocket.add_child(pad_dust)
	$WorldObjects/Rocket.add_child(exhaust_smoke)
	pad_dust.emitting = true
	exhaust_smoke.emitting = true

	dialogue.play_rocket_rumble(4.6)

	# Clear lingering surface dust off rocket hull as thrusters ignite
	var rocket_mat := rocket_sprite.material as ShaderMaterial
	if rocket_mat != null:
		var dust_clear := create_tween()
		dust_clear.tween_method(
			func(v: float) -> void:
				rocket_mat.set_shader_parameter("dust_top", v),
			rocket_mat.get_shader_parameter("dust_top"),
			0.0,
			0.45
		)

	var base_pos := rocket_sprite.position
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091

	# Phase 1: Ignition rumble & rocket shaking on the launchpad
	var ignition_elapsed := 0.0
	var ignition_duration := 1.4
	var frame_timer := 0.0
	var frame_idx := 0
	while ignition_elapsed < ignition_duration:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		ignition_elapsed += dt
		frame_timer += dt
		if not rocket_frames.is_empty() and frame_timer >= 0.085:
			frame_timer = 0.0
			frame_idx = (frame_idx + 1) % mini(2, rocket_frames.size())
			rocket_sprite.texture = rocket_frames[frame_idx]
		var shake_strength := lerpf(1.2, 3.6, minf(1.0, ignition_elapsed / ignition_duration))
		var lift_nudge := maxf(0.0, ignition_elapsed - 0.85) * 24.0
		rocket_sprite.position = base_pos + Vector2(
			rng.randf_range(-shake_strength, shake_strength),
			-lift_nudge + rng.randf_range(-shake_strength * 0.7, shake_strength * 0.7)
		)
		camera.offset = Vector2(
			rng.randf_range(-shake_strength * 0.75, shake_strength * 0.75),
			rng.randf_range(-shake_strength * 0.75, shake_strength * 0.75)
		)
		exhaust_smoke.position = rocket_sprite.position + Vector2(0, 124)

	# Phase 2: Slow accelerating liftoff until completely out of camera view
	var start_y := rocket_sprite.position.y
	var target_out_of_view_y := -580.0
	var climb_elapsed := 0.0
	var climb_duration := 3.15
	while climb_elapsed < climb_duration:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		climb_elapsed += dt
		frame_timer += dt
		if rocket_frames.size() >= 2 and frame_timer >= 0.075:
			frame_timer = 0.0
			var thrust_index := 1 + ((frame_idx + 1) % (rocket_frames.size() - 1))
			frame_idx = thrust_index
			rocket_sprite.texture = rocket_frames[thrust_index]
		var progress := clampf(climb_elapsed / climb_duration, 0.0, 1.0)
		var eased_y := lerpf(start_y, target_out_of_view_y, progress * progress * progress * 0.55 + progress * progress * 0.45)
		var shake := lerpf(3.0, 0.4, progress)
		rocket_sprite.position = Vector2(
			base_pos.x + rng.randf_range(-shake, shake),
			eased_y
		)
		var cam_shake := lerpf(2.4, 0.0, progress)
		camera.offset = Vector2(
			rng.randf_range(-cam_shake, cam_shake),
			rng.randf_range(-cam_shake, cam_shake)
		)
		exhaust_smoke.position = rocket_sprite.position + Vector2(0, 126)
		if progress > 0.48:
			pad_dust.emitting = false

	rocket_sprite.position.y = target_out_of_view_y
	rocket_sprite.visible = false
	camera.offset = Vector2.ZERO
	exhaust_smoke.emitting = false
	pad_dust.emitting = false

	await dialogue.fade_to_black(1.0)
	await get_tree().create_timer(0.35).timeout
	get_tree().change_scene_to_file(AWARD_CEREMONY_SCENE)


func _walk_player_to_rocket_hatch() -> void:
	var ramp_entry := Vector2(ROCKET_HATCH_POSITION.x, ROCKET_BOARDING_POSITION.y)
	if absf(player.position.x - ramp_entry.x) > 4.0:
		player.anim.play("walk_right" if ramp_entry.x > player.position.x else "walk_left")
		var h_dist := absf(ramp_entry.x - player.position.x)
		var h_tween := create_tween()
		h_tween.tween_property(player, "position:x", ramp_entry.x, clampf(h_dist / 120.0, 0.12, 0.55))
		await h_tween.finished

	player.anim.play("walk_up")
	var v_dist := player.position.distance_to(ROCKET_HATCH_POSITION)
	var v_tween := create_tween()
	v_tween.tween_property(player, "position", ROCKET_HATCH_POSITION, clampf(v_dist / 110.0, 0.35, 1.0))
	await v_tween.finished

	player.anim.play("idle_up")
	var enter_tween := create_tween()
	enter_tween.tween_property(player, "scale", Vector2(0.55, 0.55), 0.24)
	enter_tween.parallel().tween_property(player, "modulate:a", 0.0, 0.24)
	await enter_tween.finished
	player.visible = false


func _create_launch_particles(
	node_name: String,
	emit_pos: Vector2,
	spread_deg: float,
	vel_min: float,
	vel_max: float,
	scale_min: float,
	scale_max: float,
	start_color: Color,
	end_color: Color,
	particle_gravity: Vector2,
	particle_amount: int,
	particle_lifetime: float
) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = node_name
	particles.position = emit_pos
	particles.z_index = 6
	particles.emitting = false
	particles.amount = particle_amount
	particles.lifetime = particle_lifetime
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(26, 6)
	particles.direction = Vector2(0, 1)
	particles.spread = spread_deg
	particles.initial_velocity_min = vel_min
	particles.initial_velocity_max = vel_max
	particles.gravity = particle_gravity
	particles.scale_amount_min = scale_min
	particles.scale_amount_max = scale_max
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([start_color, end_color])
	particles.color_ramp = gradient
	return particles
