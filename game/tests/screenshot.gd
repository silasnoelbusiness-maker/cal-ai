extends Node
## Dev tool: renders the main scene to a PNG so the district can be eyeballed
## without a desktop, e.g. from CI or a headless dev box.
##
##   xvfb-run -a godot --rendering-driver opengl3 --path game \
##       res://tests/screenshot.tscn ++ out.png 8.5
##
## User args after `++`: output path, hour of day, then optional camera
## distance / yaw / pitch overrides for framing overview shots.
##
## Note: this runs under the Compatibility renderer, so SSAO is skipped and
## lighting is close to, but not identical to, the Forward+ game.

const MAIN_SCENE := preload("res://main.tscn")

var _output_path: String = "user://screenshot.png"
var _hour: float = 9.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_output_path = args[0]
	if args.size() > 1:
		_hour = args[1].to_float()

	# Set the clock before the scene exists so the HUD reads the right time
	# when it builds its labels.
	TimeManager.set_total_minutes(_hour * 60.0)
	TimeManager.clock_stopped = true

	var main := MAIN_SCENE.instantiate()
	add_child(main)

	var rig: TopDownCamera = main.get_node("CameraRig")
	if args.size() > 2:
		rig.max_distance = 400.0
		rig.distance = args[2].to_float()
	if args.size() > 3:
		rig.yaw_degrees = args[3].to_float()
	if args.size() > 4:
		rig.pitch_degrees = args[4].to_float()

	# Let the world build, the player settle and the camera reach its target.
	for i in 45:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		get_tree().quit(1)
		return
	print("Wrote ", _output_path)
	get_tree().quit(0)
