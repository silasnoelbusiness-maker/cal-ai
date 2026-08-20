extends Node3D
## Entry scene: wires the district, the player, the camera rig and the HUD
## together and gets out of the way.
##
## Keeping the wiring here rather than inside any one system means a second
## district, or a different spawn (a save file's stored position), only changes
## this file.

@onready var district: District01 = $District01
@onready var player: Player = $Player
@onready var camera_rig: TopDownCamera = $CameraRig


func _ready() -> void:
	_spawn_player()
	camera_rig.set_target(player, true)
	camera_rig.camera.current = true
	# The district places a car for the player before the registry exists to own
	# it, and so did every save written before the registry existed. Both are
	# taken onto the books here, once the world is built.
	VehicleRegistry.adopt_scene_vehicles()


func _spawn_player() -> void:
	var spawn := district.get_spawn_transform()
	player.global_position = spawn.origin
	player.velocity = Vector3.ZERO
