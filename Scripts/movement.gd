extends CharacterBody2D

# 150 is a solid walking speed for a 48px map grid
@export var speed: float = 150.0 

@onready var anim = $AnimatedSprite2D

var facing_direction: String = "down"

func _ready():
	# If a transition spawn point was set, snap the player there immediately
	if Global.target_spawn_position != Vector2.ZERO:
		global_position = Global.target_spawn_position
		facing_direction = Global.player_facing_direction
		Global.target_spawn_position = Vector2.ZERO
		
	# Play initial idle animation
	anim.play("idle_" + facing_direction)

func _physics_process(_delta):
	# get_vector automatically normalizes diagonal movement
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	velocity = direction * speed
	move_and_slide()
	
	update_animations(direction)

func update_animations(direction: Vector2):
	# Play idle animation if standing still
	if direction == Vector2.ZERO:
		anim.play("idle_" + facing_direction)
		return
		
	# Determine the 4-way animation. 
	# Checking the X axis first prioritizes left/right animations during diagonal movement.
	if direction.x != 0:
		facing_direction = "right" if direction.x > 0 else "left"
	elif direction.y != 0:
		facing_direction = "down" if direction.y > 0 else "up"
		
	anim.play("walk_" + facing_direction)
