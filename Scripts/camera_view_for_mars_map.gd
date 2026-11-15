
extends Node2D

@onready var map_sprite: Sprite2D = $Background
@onready var camera: Camera2D = $WorldObjects/CharacterBody2d/Camera2D

func _ready():
	# Check node references
	if map_sprite == null:
		push_error("Background Sprite2D not found!")
		return

	if camera == null:
		push_error("Player Camera2D not found!")
		return

	# Calculate the map's actual world boundaries
	var map_bounds: Rect2 = (
		map_sprite.get_global_transform() * map_sprite.get_rect()
	)

	# Apply boundaries to the camera
	camera.limit_left = floori(map_bounds.position.x)
	camera.limit_top = floori(map_bounds.position.y)
	camera.limit_right = ceili(map_bounds.end.x)
	camera.limit_bottom = ceili(map_bounds.end.y)
