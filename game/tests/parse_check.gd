extends SceneTree

## Loads the long scripts and says whether they parse.
##
## The headless suite takes minutes to reach its first check, and a parse error
## in it does not stop Godot — the scene simply never runs, and the process
## sits there until something kills it. That cost forty minutes once. This
## loads each script the same way the game would, with the autoloads present,
## and exits: a broken test file now fails in seconds.

const SCRIPTS: Array[String] = [
	"res://tests/smoke_test.gd",
	"res://tests/screenshot.gd",
]


func _initialize() -> void:
	var broken := 0
	for path in SCRIPTS:
		var script := load(path)
		if script == null:
			print("PARSE FAILED  ", path)
			broken += 1
		else:
			print("ok            ", path)
	print("parse check: %d broken" % broken)
	quit(1 if broken > 0 else 0)
