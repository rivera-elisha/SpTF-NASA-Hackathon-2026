extends Node2D

const DialogueController = preload("res://Scripts/mission_dialogue.gd")
const InteractiveAssets = preload("res://Scripts/interactive_assets.gd")

@onready var player: CharacterBody2D = $CharacterBody2d

var dialogue: CanvasLayer
var exercise_prompt_started := false
var exercise_sequence_running := false
var asset_dialogue_running := false
var interact_mgr: InteractiveAssets.InteractManager
var treadmill_fx: Node2D
var ared_fx: Node2D


func _ready() -> void:
	dialogue = DialogueController.new()
	add_child(dialogue)
	Global.radiation_warning_started.connect(_on_radiation_warning_started)
	Global.radiation_event_expired.connect(_on_radiation_event_expired)
	if Global.mission_complete:
		dialogue.set_mission("Mission complete.")
		return
	_setup_room2_assets()
	if Global.exercise_prompt_completed:
		if Global.part4_rocket_boarding_ready and not Global.part4_ending_reached:
			dialogue.set_mission("Return outside and board the rocket ship.", $ExitMainDoor)
		elif Global.comms_static_part3_pending and not Global.comms_part3_arrived:
			dialogue.set_mission("Return outside and go to the Communication Room.", $ExitMainDoor)
		elif Global.all_solar_panels_cleaned() and not Global.discovery_named:
			dialogue.set_mission("Return outside and check the Main Laboratory Room.", $ExitMainDoor)
		elif Global.lab_analysis_started and not Global.all_solar_panels_cleaned():
			dialogue.set_mission("Return outside and clean the solar panels.", $ExitMainDoor)
		elif Global.glowing_object_collected and not Global.lab_analysis_started:
			dialogue.set_mission("Return outside and proceed to the Main Laboratory.", $ExitMainDoor)
		else:
			dialogue.set_mission("Return outside to the outpost.", $ExitMainDoor)
		return
	dialogue.set_mission("Find the Exercise Room.", $ExerciseArea)
	$ExerciseArea.body_entered.connect(_on_exercise_area_body_entered)
	if Global.radiation_warning_active:
		dialogue.show_radiation_warning()


func _setup_room2_assets() -> void:
	interact_mgr = InteractiveAssets.create_interact_manager(
		self,
		player,
		func() -> bool: return dialogue.is_busy() or exercise_sequence_running or asset_dialogue_running
	)

	var treadmill := get_node_or_null("Sprite2D/T2 Treadmill") as Node2D
	if treadmill:
		treadmill_fx = InteractiveAssets.attach_world_fx(self, treadmill.global_position, "treadmill", Vector2(76, 48))
		interact_mgr.add_interactable(
			"treadmill",
			treadmill.global_position,
			"Sprint on T2 Treadmill",
			_on_interact_treadmill,
			78.0,
			Vector2(92, 68),
			func() -> bool: return Global.exercise_prompt_completed
		)

	var ared := get_node_or_null("Sprite2D/ARED") as Node2D
	if ared:
		ared_fx = InteractiveAssets.attach_world_fx(self, ared.global_position, "ared", Vector2(82, 54))
		interact_mgr.add_interactable(
			"ared",
			ared.global_position,
			"Lift on ARED",
			_on_interact_ared,
			86.0,
			Vector2(108, 66),
			func() -> bool: return Global.exercise_prompt_completed
		)

	var med1 := get_node_or_null("Sprite2D/medical_1") as Node2D
	if med1:
		InteractiveAssets.attach_world_fx(self, med1.global_position, "monitor_vitals", Vector2(58, 44))
		interact_mgr.add_interactable(
			"medical_vitals",
			med1.global_position,
			"Run Medical Bio-Scan",
			func() -> void: _on_interact_medical(med1.global_position),
			74.0,
			Vector2(72, 54)
		)

	var med2 := get_node_or_null("Sprite2D/medical_1/medical_2") as Node2D
	if med2:
		InteractiveAssets.attach_world_fx(self, med2.global_position, "medical_cab", Vector2(48, 38))
		interact_mgr.add_interactable(
			"medical_locker",
			med2.global_position,
			"Check Medkit Locker",
			func() -> void: _on_interact_medkit(med2.global_position),
			74.0,
			Vector2(62, 48)
		)

	var bed_nodes: Array[Node2D] = []
	for bname in ["bed4", "bed5", "bed3", "bed6"]:
		var b := get_node_or_null("Sprite2D/beds/" + bname) as Node2D
		if b:
			InteractiveAssets.attach_world_fx(self, b.global_position, "bed_berth", Vector2(54, 96))
			bed_nodes.append(b)
	if not bed_nodes.is_empty():
		var beds_center := Vector2(200, 109)
		interact_mgr.add_interactable(
			"crew_berths",
			beds_center,
			"Rest in Crew Berth",
			func() -> void: _on_interact_beds(beds_center),
			128.0,
			Vector2(210, 118)
		)

	var galley_cab := get_node_or_null("Sprite2D/food cabinet") as Node2D
	if galley_cab:
		InteractiveAssets.attach_world_fx(self, galley_cab.global_position, "galley", Vector2(72, 68))
		interact_mgr.add_interactable(
			"food_cabinet",
			galley_cab.global_position,
			"Grab Space Ration",
			func() -> void: _on_interact_galley(galley_cab.global_position, true),
			86.0,
			Vector2(108, 110)
		)

	var galley_shelf := get_node_or_null("Sprite2D/food cabinet/food shelf") as Node2D
	if galley_shelf:
		InteractiveAssets.attach_world_fx(self, galley_shelf.global_position, "galley", Vector2(68, 62))
		interact_mgr.add_interactable(
			"food_shelf",
			galley_shelf.global_position,
			"Check Ration Inventory",
			func() -> void: _on_interact_galley(galley_shelf.global_position, false),
			86.0,
			Vector2(110, 106)
		)

	var hygiene := get_node_or_null("Sprite2D/comfortRoom") as Node2D
	if hygiene:
		InteractiveAssets.attach_world_fx(self, hygiene.global_position, "hygiene_rack", Vector2(78, 92))
		interact_mgr.add_interactable(
			"comfort_room",
			hygiene.global_position,
			"Cycle Hygiene Rack",
			func() -> void: _on_interact_hygiene(hygiene.global_position),
			92.0,
			Vector2(104, 118)
		)

	var msg := get_node_or_null("Sprite2D/MSG") as Node2D
	if msg:
		InteractiveAssets.attach_world_fx(self, msg.global_position, "glovebox", Vector2(76, 68))
		interact_mgr.add_interactable(
			"msg_glovebox",
			msg.global_position,
			"Run Glovebox Study",
			func() -> void: _on_interact_msg(msg.global_position),
			88.0,
			Vector2(114, 110)
		)

	var cir := get_node_or_null("Sprite2D/CIR") as Node2D
	if cir:
		InteractiveAssets.attach_world_fx(self, cir.global_position, "combustion_rack", Vector2(76, 78))
		interact_mgr.add_interactable(
			"cir_combustion",
			cir.global_position,
			"Ignite Cool-Flame Test",
			func() -> void: _on_interact_cir(cir.global_position),
			92.0,
			Vector2(124, 126)
		)


func _run_animated_exercise_sequence() -> void:
	exercise_sequence_running = true
	var saved_pos := player.global_position
	var col := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if col:
		col.disabled = true

	var treadmill := get_node_or_null("Sprite2D/T2 Treadmill") as Node2D
	var ared := get_node_or_null("Sprite2D/ARED") as Node2D
	var treadmill_pos := treadmill.global_position + Vector2(-4, -8) if treadmill else Vector2(841, 535)
	var ared_pos := ared.global_position + Vector2(-10, -4) if ared else Vector2(1015, 500)

	# Build sleek Workout HUD + Barbell/Harness World VFX
	var hud := _WorkoutHUD.new()
	add_child(hud)
	var gear_vfx := _ExerciseGearVFX.new()
	gear_vfx.z_index = 22
	add_child(gear_vfx)

	# --- STAGE 1: T2 TREADMILL ZERO-G SPRINT ---
	var move_t := create_tween()
	move_t.tween_property(player, "global_position", treadmill_pos, 0.32).set_trans(Tween.TRANS_SINE)
	await move_t.finished

	if is_instance_valid(treadmill_fx):
		treadmill_fx.set_meta("fast_mode", true)
	hud.set_stage("STAGE 1/2: T2 TREADMILL CARDIO", "Running 1.2G harness loaded — [SPACE / CLICK] Sprint Boost!")
	gear_vfx.mode = "treadmill"
	gear_vfx.anchor = treadmill_pos

	var progress := 0.0
	var run_time := 0.0
	var step_cooldown := 0.0
	var base_sprite_pos := sprite.position if sprite else Vector2.ZERO
	while progress < 1.0 and is_inside_tree():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		run_time += dt
		var boosted := hud.consume_boost()
		var rate := 0.38
		if boosted:
			progress += 0.16
			InteractiveAssets.spawn_burst_vfx(self, player.global_position + Vector2(0, 14), Color(0.35, 0.95, 1.0, 0.95), 14, 95.0, 3.0)
			InteractiveAssets.spawn_ring_vfx(self, player.global_position, Color(0.35, 0.95, 1.0, 0.9), 34.0, 0.35)
			InteractiveAssets.spawn_floating_text(self, player.global_position + Vector2(0, -16), "TURBO STRIDE!", Color(0.4, 0.96, 1.0))
			InteractiveAssets.play_sfx(self, "interact", -9.0)
		progress = minf(1.0, progress + dt * rate)
		hud.set_progress(progress, "%d km/h" % int(lerpf(11.0, 19.0, progress)))

		if sprite:
			sprite.play("walk_right")
			sprite.speed_scale = 2.6 if boosted else 1.8
			sprite.position = base_sprite_pos + Vector2(0, -absf(sin(run_time * 16.0)) * 4.5)
		gear_vfx.phase = run_time
		gear_vfx.queue_redraw()

		step_cooldown -= dt
		if step_cooldown <= 0.0:
			step_cooldown = 0.22
			InteractiveAssets.spawn_burst_vfx(self, player.global_position + Vector2(-8, 15), Color(0.55, 0.92, 1.0, 0.8), 6, 48.0, 2.2, Vector2(-60, 10), 0.35)
			InteractiveAssets.play_sfx(self, "step", -14.0)

	if is_instance_valid(treadmill_fx):
		treadmill_fx.set_meta("fast_mode", false)
	if sprite:
		sprite.position = base_sprite_pos
		sprite.speed_scale = 1.0
	InteractiveAssets.spawn_ring_vfx(self, treadmill_pos, Color(0.35, 1.0, 0.65, 0.95), 42.0, 0.4)
	InteractiveAssets.play_sfx(self, "heal", -9.0)

	# --- STAGE 2: ARED RESISTANCE LIFTS (3 POWER REPS) ---
	var dash_t := create_tween()
	dash_t.tween_property(player, "global_position", ared_pos, 0.38).set_trans(Tween.TRANS_SINE)
	await dash_t.finished

	if is_instance_valid(ared_fx):
		ared_fx.set_meta("active_mode", true)
	gear_vfx.mode = "ared"
	gear_vfx.anchor = ared_pos
	if sprite:
		sprite.play("idle_down")
	var base_sprite_scale := sprite.scale if sprite else Vector2.ONE

	var lift_progress := 0.0
	var lift_time := 0.0
	var last_rep := 0
	while lift_progress < 1.0 and is_inside_tree():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		lift_time += dt
		var boosted := hud.consume_boost()
		if boosted:
			lift_progress += 0.16
			InteractiveAssets.play_sfx(self, "lift", -7.0)
			InteractiveAssets.spawn_burst_vfx(self, player.global_position + Vector2(0, -14), Color(1.0, 0.84, 0.28, 0.95), 16, 88.0, 3.4)
			InteractiveAssets.spawn_floating_text(self, player.global_position + Vector2(0, -22), "POWER LIFT!", Color(1.0, 0.86, 0.3))
		lift_progress = minf(1.0, lift_progress + dt * 0.38)
		var rep := mini(3, int(lift_progress * 3.0) + 1)
		if rep > last_rep:
			last_rep = rep
			InteractiveAssets.play_sfx(self, "lift", -10.0)
			InteractiveAssets.spawn_ring_vfx(self, ared_pos, Color(1.0, 0.78, 0.25, 0.92), 40.0, 0.42)
			InteractiveAssets.spawn_burst_vfx(self, ared_pos, Color(1.0, 0.85, 0.32, 0.9), 14, 72.0, 3.0)
		hud.set_stage("STAGE 2/2: ARED RESISTANCE — REP %d/3" % rep, "Vacuum cylinder load active — [SPACE / CLICK] Power Lift!")
		hud.set_progress(lift_progress, "%d kg eq." % (110 + rep * 25))

		var rep_wave := 0.5 - 0.5 * cos(lift_progress * 3.0 * TAU)
		if sprite:
			sprite.position = base_sprite_pos + Vector2(0, -rep_wave * 6.0)
			sprite.scale = Vector2(base_sprite_scale.x * (1.06 - rep_wave * 0.08), base_sprite_scale.y * (0.94 + rep_wave * 0.10))
		gear_vfx.phase = rep_wave
		gear_vfx.queue_redraw()

	if is_instance_valid(ared_fx):
		ared_fx.set_meta("active_mode", false)
	if sprite:
		sprite.position = base_sprite_pos
		sprite.scale = base_sprite_scale
		sprite.play("idle_down")

	# Return safely to pre-exercise position
	var ret_t := create_tween()
	ret_t.tween_property(player, "global_position", saved_pos, 0.32).set_trans(Tween.TRANS_SINE)
	await ret_t.finished
	if col:
		col.disabled = false

	gear_vfx.queue_free()
	hud.queue_free()

	InteractiveAssets.spawn_ring_vfx(self, player.global_position, Color(0.4, 1.0, 0.75, 0.95), 54.0, 0.55)
	InteractiveAssets.spawn_burst_vfx(self, player.global_position, Color(0.45, 0.95, 1.0, 0.95), 28, 105.0, 3.8, Vector2(0, -15), 0.75)
	InteractiveAssets.spawn_floating_text(self, player.global_position, "FITNESS & BONE DENSITY: 100%", Color(0.48, 1.0, 0.72), 1.4)
	InteractiveAssets.play_sfx(self, "success", -6.0)
	await get_tree().create_timer(0.45).timeout
	exercise_sequence_running = false


func _on_interact_treadmill() -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	var treadmill := get_node_or_null("Sprite2D/T2 Treadmill") as Node2D
	var pos := treadmill.global_position if treadmill else Vector2(845, 543)
	if is_instance_valid(treadmill_fx):
		treadmill_fx.set_meta("fast_mode", true)
	InteractiveAssets.play_sfx(self, "scan", -9.0)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.35, 0.92, 1.0, 0.9), 18, 70.0, 3.0)
	InteractiveAssets.spawn_floating_text(self, pos, "T2 BELT: 14.5 KM/H", Color(0.45, 0.95, 1.0))
	player.set_physics_process(false)
	var status := "Nominal — 1.2G harness calibrated" if Global.did_exercise else "Standby — Cardio session still recommended!"
	await dialogue.say("T2 Treadmill", "NASA COLBERT T2 Treadmill: Speed load set to 14.5 km/h with vibration-isolation mounts. Status: %s." % status, 0.0)
	player.set_physics_process(true)
	if is_instance_valid(treadmill_fx):
		treadmill_fx.set_meta("fast_mode", false)
	asset_dialogue_running = false


func _on_interact_ared() -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	var ared := get_node_or_null("Sprite2D/ARED") as Node2D
	var pos := ared.global_position if ared else Vector2(1025, 504)
	if is_instance_valid(ared_fx):
		ared_fx.set_meta("active_mode", true)
	InteractiveAssets.play_sfx(self, "lift", -8.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(1.0, 0.78, 0.25, 0.95), 40.0, 0.45)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(1.0, 0.85, 0.35, 0.9), 18, 75.0, 3.2)
	InteractiveAssets.spawn_floating_text(self, pos, "VACUUM LOAD: 160 KG", Color(1.0, 0.86, 0.32))
	player.set_physics_process(false)
	var bone := "99.4% (Peak Resistance Logged)" if Global.did_exercise else "78.0% (Zero-G Bone Loss Risk)"
	await dialogue.say("ARED Weightlifting", "Advanced Resistive Exercise Device (ARED): Dual vacuum pistons simulate Earth gravity squats and deadlifts up to 272 kg. Bone Mineral Index: %s." % bone, 0.0)
	player.set_physics_process(true)
	if is_instance_valid(ared_fx):
		ared_fx.set_meta("active_mode", false)
	asset_dialogue_running = false


func _on_interact_medical(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "heal", -8.0)
	InteractiveAssets.spawn_scan_beam_vfx(self, player.global_position, Color(0.32, 1.0, 0.65, 0.9), 44.0, 56.0, 0.75)
	InteractiveAssets.spawn_scan_beam_vfx(self, pos, Color(0.32, 0.92, 1.0, 0.9), 52.0, 44.0, 0.65)
	InteractiveAssets.spawn_burst_vfx(self, player.global_position, Color(0.4, 1.0, 0.68, 0.9), 18, 65.0, 3.0)
	var hr := "62 BPM (Athletic)" if Global.did_exercise else "96 BPM (Fatigued)"
	InteractiveAssets.spawn_floating_text(self, player.global_position, "VITALS: " + hr, Color(0.45, 1.0, 0.7))
	await get_tree().create_timer(0.45).timeout
	await dialogue.say("Medical Bio-Scanner", "Commander %s Biometrics — Heart Rate: %s | Blood O2: 99%% | Hydration: Nominal." % [Global.get_player_display_name(), hr], 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_medkit(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "heal", -9.0)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.45, 0.92, 1.0, 0.9), 16, 62.0, 2.8)
	InteractiveAssets.spawn_floating_text(self, pos, "MEDKIT STERILE: READY", Color(0.6, 0.96, 1.0))
	await dialogue.say("Medbay Supply Cabinet", "Emergency trauma kits, radiation potassium-iodide packs, and regolith eyewash stocked for EVA emergencies.", 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_beds(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "snooze", -9.0)
	InteractiveAssets.spawn_burst_vfx(self, player.global_position, Color(0.55, 0.78, 1.0, 0.9), 16, 48.0, 2.8, Vector2(0, -35), 0.9)
	InteractiveAssets.spawn_floating_text(self, player.global_position, "Z z z ... Rested!", Color(0.7, 0.88, 1.0), 1.3)
	await dialogue.say("Crew Sleeping Quarters", "4 restraints-equipped microgravity sleep berths. Ventilation fan noise kept steady so CO2 never pools while sleeping!", 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_galley(pos: Vector2, is_cabinet: bool) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "pickup", -9.0)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(1.0, 0.8, 0.35, 0.9), 18, 60.0, 3.0)
	InteractiveAssets.spawn_floating_text(self, pos, "+RATION HYDRATED!" if is_cabinet else "RATION SUPPLY: 100%", Color(1.0, 0.88, 0.45))
	var msg := (
		"Galley Warmer & Rehydrator: Heated pouches of thermostabilized steak, freeze-dried strawberries, and zero-G coffee ready for 2,800 kcal/Sol."
		if is_cabinet
		else "Food Storage Shelf: 180 Sols of shelf-stable space rations indexed by crew member, plus hydroponic greens reserve."
	)
	await dialogue.say("Habitat Galley", msg, 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_hygiene(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "mist", -8.0)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.55, 0.95, 1.0, 0.9), 20, 72.0, 3.0, Vector2(0, -25), 0.7)
	InteractiveAssets.spawn_floating_text(self, pos, "H2O RECOVERY: 98%", Color(0.65, 0.96, 1.0))
	await dialogue.say("Waste & Hygiene Compartment (LAB1P2)", "Suction airflow funnel and foot restraints keep zero-G hygiene clean, recovering 98% of wastewater back into potable drinking water.", 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_msg(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "scan", -8.0)
	InteractiveAssets.spawn_scan_beam_vfx(self, pos, Color(0.38, 0.95, 1.0, 0.9), 84.0, 76.0, 0.75)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(0.5, 0.95, 1.0, 0.92), 22, 74.0, 3.2)
	InteractiveAssets.spawn_floating_text(self, pos, "SEALED CONTAINMENT ACTIVE", Color(0.55, 0.95, 1.0))
	await dialogue.say("Microgravity Science Glovebox (MSG)", "Negative-pressure sealed glovebox for handling fine Martian regolith, perchlorate salts, and biological assays safely without cabin contamination.", 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


func _on_interact_cir(pos: Vector2) -> void:
	if asset_dialogue_running:
		return
	asset_dialogue_running = true
	player.set_physics_process(false)
	InteractiveAssets.play_sfx(self, "flame", -7.0)
	InteractiveAssets.spawn_ring_vfx(self, pos, Color(0.35, 0.85, 1.0, 0.95), 42.0, 0.45)
	InteractiveAssets.spawn_burst_vfx(self, pos, Color(1.0, 0.65, 0.25, 0.95), 24, 82.0, 3.4)
	InteractiveAssets.spawn_floating_text(self, pos, "SPHERICAL COOL FLAME IGNITED!", Color(0.65, 0.92, 1.0))
	await dialogue.say("Combustion Integrated Rack (CIR)", "In reduced gravity, flames burn as clean blue spheres ('cool flames') without buoyancy convection — testing ultra-low-emission spacecraft propellant safety.", 0.0)
	player.set_physics_process(true)
	asset_dialogue_running = false


class _WorkoutHUD extends CanvasLayer:
	var panel: PanelContainer
	var stage_label: Label
	var detail_label: Label
	var bar: ProgressBar
	var stat_label: Label
	var _boost_queued := false

	func _init() -> void:
		layer = 18
		panel = PanelContainer.new()
		panel.position = Vector2(286, 18)
		panel.size = Vector2(580, 108)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.09, 0.16, 0.94)
		sb.border_color = Color(0.35, 0.82, 1.0, 0.95)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", sb)
		add_child(panel)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		panel.add_child(vb)

		var row := HBoxContainer.new()
		vb.add_child(row)
		stage_label = Label.new()
		stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_label.add_theme_font_size_override("font_size", 16)
		stage_label.add_theme_color_override("font_color", Color(0.45, 0.92, 1.0))
		row.add_child(stage_label)

		stat_label = Label.new()
		stat_label.add_theme_font_size_override("font_size", 15)
		stat_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
		row.add_child(stat_label)

		detail_label = Label.new()
		detail_label.add_theme_font_size_override("font_size", 13)
		detail_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		vb.add_child(detail_label)

		bar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 18)
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.show_percentage = false
		vb.add_child(bar)

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_E]:
			_boost_queued = true
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_boost_queued = true

	func consume_boost() -> bool:
		var hit := _boost_queued
		_boost_queued = false
		return hit

	func set_stage(title: String, detail: String) -> void:
		stage_label.text = title
		detail_label.text = detail

	func set_progress(p: float, stat_text: String) -> void:
		bar.value = clampf(p * 100.0, 0.0, 100.0)
		stat_label.text = stat_text


class _ExerciseGearVFX extends Node2D:
	var mode := "treadmill"
	var anchor := Vector2.ZERO
	var phase := 0.0

	func _draw() -> void:
		if mode == "treadmill":
			# Bungee zero-G harness straps + motion wind lines
			var top_l := anchor + Vector2(-18, -32)
			var top_r := anchor + Vector2(18, -32)
			var waist := anchor + Vector2(0, 2)
			draw_line(top_l, waist + Vector2(-5, 0), Color(0.45, 0.92, 1.0, 0.68), 2.0)
			draw_line(top_r, waist + Vector2(5, 0), Color(0.45, 0.92, 1.0, 0.68), 2.0)
			for i in 4:
				var u := fmod(phase * 3.5 + float(i) * 0.25, 1.0)
				var lx := anchor.x + 12.0 - u * 44.0
				var ly := anchor.y - 10.0 + float(i) * 7.0
				draw_line(Vector2(lx, ly), Vector2(lx - 14.0, ly), Color(0.7, 0.96, 1.0, (1.0 - u) * 0.75), 1.8)
		elif mode == "ared":
			# Glowing ARED resistance barbell over shoulders
			var bar_y := anchor.y - 10.0 - phase * 12.0
			draw_line(Vector2(anchor.x - 24.0, bar_y), Vector2(anchor.x + 24.0, bar_y), Color(0.88, 0.92, 1.0, 0.95), 3.4)
			draw_rect(Rect2(anchor.x - 27.0, bar_y - 6.0, 5.0, 12.0), Color(1.0, 0.72, 0.22, 0.95), true)
			draw_rect(Rect2(anchor.x + 22.0, bar_y - 6.0, 5.0, 12.0), Color(1.0, 0.72, 0.22, 0.95), true)
			# Force cables down to platform
			draw_line(Vector2(anchor.x - 18.0, bar_y), Vector2(anchor.x - 18.0, anchor.y + 18.0), Color(0.4, 0.88, 1.0, 0.55), 1.6)
			draw_line(Vector2(anchor.x + 18.0, bar_y), Vector2(anchor.x + 18.0, anchor.y + 18.0), Color(0.4, 0.88, 1.0, 0.55), 1.6)


func _on_exercise_area_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D or exercise_prompt_started:
		return
	exercise_prompt_started = true
	player.set_physics_process(false)
	await dialogue.say(
		"Exercise Room",
		"This is the Exercise Room where we will train your bones and muscles just like on Earth."
	)
	var exercised: bool = await dialogue.choose("Exercise", "Start Exercise?", "Yes", "No")
	Global.exercise_prompt_completed = true
	Global.did_exercise = exercised
	if exercised:
		dialogue.hide_dialogue()
		await _run_animated_exercise_sequence()
		await dialogue.say("Exercise", "Exercise complete. T2 cardio and ARED resistance training logged! Great work, Commander!")
		Global.movement_speed_multiplier = 1.0
	else:
		InteractiveAssets.spawn_burst_vfx(self, player.global_position, Color(0.75, 0.52, 0.35, 0.85), 16, 48.0, 3.0)
		InteractiveAssets.spawn_floating_text(self, player.global_position, "FATIGUE: -50% SPEED", Color(1.0, 0.55, 0.35))
		Global.movement_speed_multiplier = 0.5
		await dialogue.say("Exercise", "You skipped exercise. Your movement will deteriorate on Mars.")
	dialogue.set_mission("Return outside to the outpost.", $ExitMainDoor)
	player.set_physics_process(true)
	Global.static_message_pending = true


func _on_radiation_warning_started() -> void:
	dialogue.show_radiation_warning()


func _on_radiation_event_expired() -> void:
	dialogue.show_game_over("How I wish I was able to find it... The radiation storm caught me outside.")
