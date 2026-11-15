
extends CharacterBody2D

@export var speed: float = 150.0

@onready var anim = $AnimatedSprite2D

var facing_direction: String = "down"


func _ready():
	# Restore the player's facing direction
	if Global.player_facing_direction in ["down", "up", "left", "right"]:
		facing_direction = Global.player_facing_direction

	anim.play("idle_" + facing_direction)

	# Wait until the new scene is fully loaded
	call_deferred("_apply_transition_spawn")


func _apply_transition_spawn():
	# Use a named Marker2D if one was provided
	if Global.target_spawn_marker != &"":
		var scene_root = get_tree().current_scene

		if scene_root == null:
			push_error("Current scene not found!")
			return

		var marker = scene_root.find_child(
			String(Global.target_spawn_marker),
			true,
			false
		)

		if marker is Marker2D:
			global_position = marker.global_position

			Global.target_spawn_marker = &""
			Global.target_spawn_position = Vector2.ZERO
		else:
			push_error(
				"Spawn marker not found: " +
				String(Global.target_spawn_marker)
			)

		return

	# Backwards compatibility with your old coordinate-based spawns
	if Global.target_spawn_position != Vector2.ZERO:
		global_position = Global.target_spawn_position
		Global.target_spawn_position = Vector2.ZERO


func _physics_process(_delta):
	var direction = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
        "move_down"
	)

	velocity = direction * speed
	move_and_slide()

	update_animations(direction)


func update_animations(direction: Vector2):
	if direction == Vector2.ZERO:
		anim.play("idle_" + facing_direction)
		return

	# Prioritize horizontal animations during diagonal movement
	if direction.x != 0:
		facing_direction = "right" if direction.x > 0 else "left"
	elif direction.y != 0:
		facing_direction = "down" if direction.y > 0 else "up"

	anim.play("walk_" + facing_direction)
