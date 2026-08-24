class_name CharacterKit
extends RefCounted
## Builds a stylized humanoid out of primitives, and hands back the joints.
##
## One builder for every person in the game — the player, the crowd, the police,
## the staff behind a counter — because a city where the player is a modelled
## character and the pedestrians are capsules reads worse than one where
## everybody is the same kind of drawing.
##
## The figure is deliberately simple: rounded torso, separate head with hair,
## two arms, two legs, shoes. What it buys is a **silhouette**, which is the only
## thing that survives the elevated camera. Micro-detail on a face nobody can see
## from twelve metres up is wasted, so there is none.
##
## Everything is built at the look's height and parented under a single pivot,
## so `scale` on the pivot is a free way to make somebody shorter without
## rebuilding them.

## The parts an animator needs to move. Returned as a plain object rather than
## looked up by name every frame.
class Rig extends RefCounted:
	var root: Node3D = null
	var hips: Node3D = null
	var chest: Node3D = null
	var head: Node3D = null
	var arm_left: Node3D = null
	var arm_right: Node3D = null
	## Elbows. Separate from the shoulder so an arm can bend rather than only
	## swing — the difference between somebody standing and a shop dummy.
	var fore_left: Node3D = null
	var fore_right: Node3D = null
	var leg_left: Node3D = null
	var leg_right: Node3D = null
	## Height the figure was built at, so callers can place things on it.
	var height: float = 1.78


## Proportions as fractions of total height. Stylized rather than anatomical:
## the head is a little large and the legs a little short, which is what keeps a
## figure readable when it is 40 pixels tall.
const HEAD_RATIO := 0.158
const CHEST_TOP := 0.83
const HIP_HEIGHT := 0.50
const SHOULDER_HEIGHT := 0.80
const ARM_LENGTH := 0.30
const LEG_LENGTH := 0.50


## Builds a figure under `parent` and returns its rig.
##
## `cast_shadow` is off for crowd members: forty shadow-casting people on a
## street costs more than it adds, and the player and the police — the two
## figures the eye actually follows — keep theirs.
static func build(parent: Node3D, look: CharacterLook, cast_shadow: bool = true) -> Rig:
	var rig := Rig.new()
	rig.height = look.height

	var skin := Palette.tinted(&"skin", look.skin)
	var cloth := Palette.tinted(&"cloth", look.top)
	var trim := Palette.tinted(&"cloth", look.accent)
	var trousers := Palette.tinted(&"denim", look.legs)
	var boots := Palette.tinted(&"leather", look.shoes)
	var hair_mat := Palette.tinted(&"cloth", look.hair)

	var h := look.height
	var shoulders := 0.42 * h / 1.78 * look.shoulder_scale()
	var waist := 0.30 * h / 1.78 * look.waist_scale()
	var depth := 0.23 * h / 1.78 * look.waist_scale()

	rig.root = Node3D.new()
	rig.root.name = "Figure"
	parent.add_child(rig.root)

	# --- Hips and legs -----------------------------------------------------
	rig.hips = Node3D.new()
	rig.hips.name = "Hips"
	rig.hips.position = Vector3(0.0, h * HIP_HEIGHT, 0.0)
	rig.root.add_child(rig.hips)

	CityKit.add_box(
		rig.hips, "Pelvis", Vector3(0.0, -h * 0.02, 0.0),
		Vector3(waist, h * 0.10, depth), trousers, false, cast_shadow
	)

	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0.0 else "LegR"
		leg.position = Vector3(side * waist * 0.26, -h * 0.05, 0.0)
		rig.hips.add_child(leg)
		if side < 0.0:
			rig.leg_left = leg
		else:
			rig.leg_right = leg

		var thigh := h * LEG_LENGTH * 0.55
		var shin := h * LEG_LENGTH * 0.45
		CityKit.add_box(
			leg, "Thigh", Vector3(0.0, -thigh * 0.5, 0.0),
			Vector3(waist * 0.40, thigh, depth * 0.72), trousers, false, cast_shadow
		)
		CityKit.add_box(
			leg, "Shin", Vector3(0.0, -thigh - shin * 0.5, 0.0),
			Vector3(waist * 0.34, shin, depth * 0.62), trousers, false, cast_shadow
		)
		# The shoe sticks forward, which is most of what tells you which way a
		# stationary person is facing from directly above.
		CityKit.add_box(
			leg, "Shoe", Vector3(0.0, -thigh - shin - h * 0.020, depth * 0.18),
			Vector3(waist * 0.44, h * 0.045, depth * 1.05), boots, false, cast_shadow
		)

	# --- Chest, arms, head -------------------------------------------------
	rig.chest = Node3D.new()
	rig.chest.name = "Chest"
	rig.chest.position = Vector3(0.0, h * (CHEST_TOP - HIP_HEIGHT) - h * 0.14, 0.0)
	rig.hips.add_child(rig.chest)

	var torso_height := h * 0.26
	# Tapered, not a slab: a narrow waist under a broader chest under an accent
	# yoke at the very top. Three boxes, and it is the difference between a
	# person and a crate with a head on it.
	CityKit.add_box(
		rig.chest, "Waist", Vector3(0.0, -torso_height * 0.34, 0.0),
		Vector3(shoulders * 0.66, torso_height * 0.38, depth * 0.86),
		cloth, false, cast_shadow
	)
	CityKit.add_box(
		rig.chest, "Torso", Vector3(0.0, torso_height * 0.06, 0.0),
		Vector3(shoulders * 0.80, torso_height * 0.56, depth), cloth, false, cast_shadow
	)
	CityKit.add_box(
		rig.chest, "Shoulders", Vector3(0.0, torso_height * 0.38, 0.0),
		Vector3(shoulders, torso_height * 0.26, depth * 0.94), cloth, false, cast_shadow
	)
	# A collar band in the accent colour, on top of the shoulders rather than
	# across the chest. Enough to stop the torso being one flat colour without
	# turning everybody into a hi-vis worker.
	CityKit.add_box(
		rig.chest, "Collar", Vector3(0.0, torso_height * 0.50, 0.0),
		Vector3(shoulders * 0.98, torso_height * 0.08, depth * 0.90), trim, false, false
	)

	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0.0 else "ArmR"
		# Clear of the torso, so both arms are visible in silhouette from above
		# instead of being swallowed by the chest.
		arm.position = Vector3(side * shoulders * 0.58, torso_height * 0.34, 0.0)
		rig.chest.add_child(arm)
		if side < 0.0:
			rig.arm_left = arm
		else:
			rig.arm_right = arm

		var upper := h * ARM_LENGTH * 0.55
		var fore := h * ARM_LENGTH * 0.45
		CityKit.add_box(
			arm, "Upper", Vector3(0.0, -upper * 0.5, 0.0),
			Vector3(shoulders * 0.20, upper, depth * 0.52), cloth, false, cast_shadow
		)
		# The forearm hangs off its own joint at the elbow, so the animator can
		# bend an arm instead of only swinging the whole thing from the
		# shoulder. Two arms that are dead straight from shoulder to fingertip
		# are what makes a standing figure read as a shop dummy.
		var elbow := Node3D.new()
		elbow.name = "ForeL" if side < 0.0 else "ForeR"
		elbow.position = Vector3(0.0, -upper, 0.0)
		arm.add_child(elbow)
		if side < 0.0:
			rig.fore_left = elbow
		else:
			rig.fore_right = elbow
		CityKit.add_box(
			elbow, "Fore", Vector3(0.0, -fore * 0.5, 0.0),
			Vector3(shoulders * 0.17, fore, depth * 0.46), cloth, false, cast_shadow
		)
		# A cuff in the skin colour where the sleeve ends, so the hand is not
		# the only thing separating an arm from a stick.
		CityKit.add_box(
			elbow, "Cuff", Vector3(0.0, -fore - h * 0.006, 0.0),
			Vector3(shoulders * 0.175, h * 0.014, depth * 0.47), skin, false, false
		)
		# Slightly wider than the forearm, or a hand does not read at all.
		CityKit.add_sphere(
			elbow, "Hand", Vector3(0.0, -fore - h * 0.026, 0.0),
			Vector3(shoulders * 0.24, shoulders * 0.26, shoulders * 0.25), skin
		)

	rig.head = Node3D.new()
	rig.head.name = "Head"
	# Clear of the shoulders, with the neck visible between: a head resting
	# straight on the collar is the single strongest "placeholder" cue there is.
	rig.head.position = Vector3(0.0, torso_height * 0.54 + h * HEAD_RATIO * 0.72, 0.0)
	rig.chest.add_child(rig.head)

	var head_size := h * HEAD_RATIO
	# A short neck, or the head floats.
	CityKit.add_box(
		rig.head, "Neck", Vector3(0.0, -head_size * 0.56, 0.0),
		Vector3(head_size * 0.38, head_size * 0.42, head_size * 0.38), skin, false, cast_shadow
	)
	CityKit.add_box(
		rig.head, "Skull", Vector3.ZERO,
		Vector3(head_size * 0.78, head_size * 0.94, head_size * 0.84), skin, false, cast_shadow
	)
	# A nose. One box, and it is the difference between a person and a die.
	CityKit.add_box(
		rig.head, "Face", Vector3(0.0, -head_size * 0.06, -head_size * 0.47),
		Vector3(head_size * 0.20, head_size * 0.16, head_size * 0.10), skin, false, false
	)
	_add_hair(rig.head, look, head_size, hair_mat, trim, cast_shadow)

	return rig


## Hair, or a cap. Built on top of the skull rather than replacing it, so a
## style is one or two boxes.
static func _add_hair(
	head: Node3D,
	look: CharacterLook,
	head_size: float,
	hair_mat: StandardMaterial3D,
	trim: StandardMaterial3D,
	cast_shadow: bool
) -> void:
	match look.hair_style:
		CharacterLook.HairStyle.BALD:
			return
		CharacterLook.HairStyle.CAP:
			CityKit.add_box(
				head, "Cap", Vector3(0.0, head_size * 0.40, 0.0),
				Vector3(head_size * 0.88, head_size * 0.26, head_size * 0.92),
				hair_mat, false, cast_shadow
			)
			CityKit.add_box(
				head, "Peak", Vector3(0.0, head_size * 0.33, -head_size * 0.60),
				Vector3(head_size * 0.72, head_size * 0.07, head_size * 0.34),
				hair_mat, false, false
			)
			# The badge. Small, but it is what makes an officer read as police
			# from above rather than as somebody in a dark coat.
			CityKit.add_box(
				head, "CapBadge", Vector3(0.0, head_size * 0.44, -head_size * 0.44),
				Vector3(head_size * 0.20, head_size * 0.10, head_size * 0.06),
				trim, false, false
			)
		CharacterLook.HairStyle.BUN:
			CityKit.add_box(
				head, "Hair", Vector3(0.0, head_size * 0.34, 0.02),
				Vector3(head_size * 0.84, head_size * 0.38, head_size * 0.90),
				hair_mat, false, cast_shadow
			)
			CityKit.add_sphere(
				head, "Bun", Vector3(0.0, head_size * 0.34, head_size * 0.50),
				Vector3(head_size * 0.42, head_size * 0.42, head_size * 0.42), hair_mat
			)
		CharacterLook.HairStyle.CROP:
			CityKit.add_box(
				head, "Hair", Vector3(0.0, head_size * 0.36, 0.0),
				Vector3(head_size * 0.84, head_size * 0.30, head_size * 0.88),
				hair_mat, false, cast_shadow
			)
		_:
			CityKit.add_box(
				head, "Hair", Vector3(0.0, head_size * 0.32, 0.02),
				Vector3(head_size * 0.86, head_size * 0.40, head_size * 0.88),
				hair_mat, false, cast_shadow
			)


## Kit on top of a built figure: a stab vest and belt for an officer, an apron
## for retail staff. Kept apart from `build` so the same figure can change role.
static func add_uniform(rig: Rig, look: CharacterLook) -> void:
	if rig == null or rig.chest == null:
		return
	var h := rig.height
	var shoulders := 0.42 * h / 1.78 * look.shoulder_scale()
	var depth := 0.23 * h / 1.78 * look.waist_scale()

	match look.category:
		CharacterLook.Category.POLICE:
			var vest := Palette.tinted(&"leather", look.top.darkened(0.35))
			CityKit.add_box(
				rig.chest, "Vest", Vector3(0.0, -h * 0.01, 0.0),
				Vector3(shoulders * 1.02, h * 0.17, depth * 1.14), vest, false, false
			)
			CityKit.add_box(
				rig.chest, "Badge", Vector3(-shoulders * 0.24, h * 0.03, -depth * 0.60),
				Vector3(shoulders * 0.16, h * 0.022, h * 0.010),
				Palette.tinted(&"metal_pale", look.accent), false, false
			)
			var belt := Palette.tinted(&"leather", Color(0.114, 0.118, 0.133))
			CityKit.add_box(
				rig.hips, "Belt", Vector3(0.0, h * 0.015, 0.0),
				Vector3(shoulders * 0.80, h * 0.030, depth * 1.10), belt, false, false
			)
		CharacterLook.Category.RETAIL:
			var apron := Palette.tinted(&"cloth", look.accent)
			CityKit.add_box(
				rig.chest, "Apron", Vector3(0.0, -h * 0.03, -depth * 0.54),
				Vector3(shoulders * 0.70, h * 0.20, h * 0.008), apron, false, false
			)
		_:
			pass
