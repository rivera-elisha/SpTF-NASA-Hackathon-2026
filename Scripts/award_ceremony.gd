extends Control

const DialogueController = preload("res://Scripts/mission_dialogue.gd")
const AWARD_FEMALE_PATH := "res://Assets/Award scene/Award_Scene_Female.png"
const AWARD_MALE_PATH := "res://Assets/Award scene/Award_Scene_Male.png"

@onready var ceremony_image: TextureRect = $CeremonyImage

var dialogue: CanvasLayer


func _ready() -> void:
	var is_female := Global.player_gender.strip_edges().to_lower() == "female"
	var image_path := AWARD_FEMALE_PATH if is_female else AWARD_MALE_PATH
	ceremony_image.texture = load(image_path) as Texture2D

	_create_ceremony_confetti()

	dialogue = DialogueController.new()
	add_child(dialogue)
	dialogue.set_hud_visible(false)

	call_deferred("_run_ceremony_sequence")


func _create_ceremony_confetti() -> void:
	var confetti := CPUParticles2D.new()
	confetti.name = "CeremonyConfetti"
	confetti.z_index = 2
	confetti.amount = 36
	confetti.lifetime = 4.2
	confetti.preprocess = 1.6
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(580.0, 20.0)
	confetti.position = Vector2(576.0, -10.0)
	confetti.direction = Vector2(0, 1)
	confetti.spread = 22.0
	confetti.initial_velocity_min = 40.0
	confetti.initial_velocity_max = 88.0
	confetti.gravity = Vector2(0, 12)
	confetti.scale_amount_min = 3.5
	confetti.scale_amount_max = 7.0
	var palette := Gradient.new()
	palette.colors = PackedColorArray([
		Color("ffd66b", 0.9),
		Color("71dcff", 0.85),
		Color("ffffff", 0.7),
		Color("ffd66b", 0.0)
	])
	confetti.color_ramp = palette
	add_child(confetti)


func _run_ceremony_sequence() -> void:
	await dialogue.fade_from_black(1.0, true)
	dialogue.play_ceremony_ambiance()
	await get_tree().create_timer(0.65).timeout

	var commander := Global.get_player_display_name()
	var discovery := Global.discovery_name if not Global.discovery_name.is_empty() else "the Mars sample"
	Global.part4_ending_reached = true
	Global.mission_complete = true

	await dialogue.say(
		"Astronaut Loise",
		"Commander %s, we commend you for your discovery of %s that brings new knowledge within the Science community. We hope you will continue to explore space and beyond." % [
			commander, discovery
		]
	)
	await dialogue.show_end_credits(
		"ENDING 2 OF 2 — RETURN TO EARTH",
		"Mission Accomplished — Commended for discovering %s on Mars." % discovery,
		"Outcome: Safely Returned Home to Earth"
	)
